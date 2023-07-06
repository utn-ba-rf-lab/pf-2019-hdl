/* serializer.v realiza varias tareas.
1. Espera recibir "UTN"
2. Luego envía "UTNv1"
3. Lee constantemente la FIFO caracteres desde la PC a una tasa comprometida de 8000 caracteres por segundo, impuesta por Mercurial (PF-2019).
Este código lo que lee del FTDI lo almacena en dato_rx. 
La FIFO es bloqueante, es decir no admite otro dato de la PC si no se lee el anterior.

Significado de los leds
0 - Prende y Apaga cada un segundo
1 - Toggle cada vez que se recibe un dato
2 - Encendido significa que transmite un dato
3 - Apagado significa FTDI habilitado para transmitir 
4 - Se apaga cuando hay un dato para leer
5 - Apaga si está en estado operativo (recibió "UTN", envió UTNv1 entró en régimen)
6 - Prende si recibió una "L"
7 - Prende si recibió una "H"
 
*/

/* module */
module top_module (
    /* I/O */
    input hwclk,                /*Clock*/
    input reset_btn,            /*Botón de reset*/
    inout [7:0] in_out_245,     /*Bus de datos con el FTDI*/
    input txe_245,
    input rxf_245,
    output rx_245,
    output wr_245,
    output [7:0] leds,
    output pin_L23B,
    output pin_L4B,
    output sdata,
    output bclk,
    output nsync);              /*SYNC del AD5061*/

    localparam PAM_CLKS_PER_BCLK = 4;
    localparam PAM_DATA_LENGHT = 24;
    
    // Estados para el DAC
    localparam ST_IDLE = 0;
    localparam ST_RUNNING = 1;
    localparam ST_BYTE_LOW = 2; 
    localparam ST_BYTE_HIGH = 3;
    
    localparam WIDTH_COUNT_BCLK = $clog2(PAM_CLKS_PER_BCLK);
    localparam WIDTH_COUNT_BITS = $clog2(PAM_DATA_LENGHT);
    
    reg [25:0] counter = 26'b0;     // Counter register - hwclk: 12MHz -> max counter 12e6
    reg [10:0] counter_8K = 11'b0;
    reg [7:0] dato,dato_tx,dato_rx = 8'b0;
    reg haydato,transmitiendo,reset,llego_dato = 1'b0;
    reg dato_leido = 1'b1;
    reg oe = 1'b0;                              // Output Enable
    reg tiempo = 1'b0;                          // Pasa a uno cada 1/8000 Sg.
    reg [3:0] estado = 4'b0;                    // estado indica en que estado está la placa
    reg a1 = 1'b0;                              // Toggle cada medio segundo
    reg a2 = 1'b0;                              // Almacena el estado anterior de a1 en el always que evalúa estado del FTDI
    reg [11:0] c1 = 12'd2000;                   // Desciende por cada carácter recibido
    reg samp_rate_error = 1'b0;                 // Va a uno si no se cumple con la tasa de muestras
    reg [1:0] c2 = 2'd3;                        // Contador de tiempo (igual a c2*0.5 Sg) para activar el WatchDog
    reg [1:0] estado_dac = ST_IDLE;             // Estado del DAC
    reg [23:0] sample_reg = 24'd0;              // Registro para enviar dato al DAC
    reg [WIDTH_COUNT_BCLK-1:0] counter_bclk;    // Contador de decimación para el clock del DAC
    reg [WIDTH_COUNT_BITS-1:0] counter_bits;    // Contador de bits enviados al DAC por muestra
    reg [15:0] muestra = 16'd0;                 // El valor que va al DAC
    reg muestra_lista = 1'b0;                   // Vale uno para ordenar al DAC que lea muestra
    reg dac_idle = 1'b1;                        // Vale uno si el DAC puede iniciar conversión
    reg byte_low = 1'b1;                        // Se levanta cuando lee un byte

/*
estado = 0 Inicio, espera "U"
estado = 1 Recibió "U", espera "T"
estado = 2 Recibió "T", espera "N"
estado = 3 Envia "U"
estado = 4 Envia "T"
estado = 5 Envia "N"
estado = 6 Envia "v"
estado = 7 Envia "1"
estado = 8 Envia "\n"
estado = 9 Detector sin WatchDog
estado = 10 Detector con WatchDog
*/
    
    assign in_out_245 = oe ? dato_tx : 8'bZ;
    assign pin_L23B = dac_idle; // antes tiempo, bclk, llego_dato, dac_idle, nsync
    assign pin_L4B = llego_dato; // antes nsync
    assign sdata = sample_reg[23];

    /* always */
    always @ (posedge hwclk) begin
        reset <= reset;
        a1 <= a1;
        counter <= counter + 1;
        leds[2] <= ~wr_245;
        leds[3] <= txe_245;
        leds[4] <= rxf_245;  // Se baja al recibir.

        // ¿Botón de reset oprimido?
        if (reset_btn && !reset) begin
            counter <= 26'd0;
            leds[0] <= 1'b0;
            a1 <= 0;
            reset <= 1'b1;
        end

        // Antirebote de botón reset, temporiza 100 uSg.
        if ( counter == 26'd1200 && reset ) begin
            counter <= 26'd0;
            reset <= 1'b0;
        end
	
	// seconds counter
        if ( counter == 26'd6000000 ) begin
            counter <= 26'd0;
            a1 <= ~a1;      // Pasó 0.5 Sg Toggle
            leds[0] <= (a1) ? 1'b1 : 1'b0;
        end
        leds[0] <= ((a1 == 1'b1) && (counter <= 26'd1200000)) ? 1'b1 : 1'b0;
    end
    
    // Máquina de estados
    always @ (posedge hwclk) begin
        estado <= estado;
        a2 <= a2;
        c1 <= c1;
        c2 <= c2;
        samp_rate_error <= samp_rate_error;
        if (reset) begin
            samp_rate_error <= 1'b0;
            estado <= 4'd0;
        end
        else if (llego_dato) begin
            case (estado)
                // Si estoy en estado 0 y recibo "U", paso a estado 1
                4'd0 : estado = (dato_rx == 8'd85) ? 4'd1 : 4'd0;
                // Si estoy en estado 1 y recibo "T", paso a estado 2
                4'd1 : estado = (dato_rx == 8'd84) ? 4'd2 : 4'd0;
                // Si estoy en estado 2 y recibo "N", paso a estado 3
                4'd2 : estado = (dato_rx == 8'd78) ? 4'd3 : 4'd0;
    	  endcase
    	  if (estado != 4'd10) leds[1] <= ~leds[1];
        end
        else if (haydato && !transmitiendo) begin
            case (estado)
                // Si estoy en estado 3, paso a estado 4 y así sucesivamente
                4'd3 : estado <= 4'd4;
                4'd4 : estado <= 4'd5;
                4'd5 : estado <= 4'd6;
                4'd6 : estado <= 4'd7;
                4'd7 : estado <= 4'd8;
                4'd8 : begin
                    c2 <= 2'd3;
                    estado <= 4'd9;
                    end
            endcase        
        end

        else if (estado == 4'd0) begin
            samp_rate_error <= 1'b0;
        end

        else if (estado == 4'd9) begin
            if (a1 != a2) begin
                c2 <= c2 - 1;
                if (c2 == 2'd0) begin
                    c1 = 12'd0;
                    estado <= 4'd10;
                end
                a2 <= a1;
            end
        end
        
        if (estado == 4'd10) begin
            // Descuento c1 si corresponde
            if (llego_dato && c1 != 12'd0) begin
                c1 <= c1 - 1;
            end
            else begin
            // Cada 0.5 Sg evalúo c1 y recargo
            if (a1 != a2) begin
                samp_rate_error <= (c1 != 12'd0) ? 1'b1 : 1'b0;
                c1 = 12'd2000;
                leds[1] <= ~leds[1];
                a2 <= a1;
            end
            end
            if (samp_rate_error) begin
                leds[1] <= 1'b0;            
                estado <= 4'd0;
            end
        end
    end

    // Lógica de serializer
    always @ (posedge hwclk) begin
        muestra <= muestra;    
        muestra_lista <= muestra_lista;
        byte_low <= byte_low;
        leds[7] <= (estado_dac == ST_RUNNING) ? 1'b1 : 1'b0;
        if (estado == 4'd0) begin
            leds[5] <= 1;
            leds[6] <= 0;
            haydato <= 1'b0;
            byte_low <= 1'b1;
            muestra <= 16'd0;
            muestra_lista <= 1'b0;
        end
        else if (estado == 4'd3) begin
            dato = 8'd85;
            haydato <= 1'b1;
        end
        else if (estado == 4'd4) begin
            dato = 8'd84;
            haydato <= 1'b1;
        end
        else if (estado == 4'd5) begin
            dato = 8'd78;
            haydato <= 1'b1;
        end
        else if (estado == 4'd6) begin
            dato = 8'd118;
            haydato <= 1'b1;
        end
        else if (estado == 4'd7) begin
            dato = 8'd49;
            haydato <= 1'b1;
        end
        else if (estado == 4'd8) begin
            dato = 8'd10;
	    haydato <= 1'b1;
	end
        else if (estado == 4'd9) begin
	    haydato <= 1'b0;
	end
        else if (estado == 4'd10) begin
            leds[5] <= 0;
            if (llego_dato && byte_low) begin
                muestra[7:0] = dato_rx;            
                byte_low <= 1'b0;
            end
            else if(llego_dato && !byte_low) begin
                muestra[15:8] = dato_rx;
                byte_low <= 1'b1;
                if (dac_idle) begin
                    muestra_lista <= 1'b1;
                end
            end
            else if (muestra_lista && !dac_idle) begin
                muestra_lista <= 1'b0;
            end
        end
    end

    // Evalua estado del FTDI
    always @ (posedge hwclk) begin
        counter_8K = tiempo ? counter_8K : counter_8K + 1;
        if ( counter_8K == 11'd750 ) begin
            counter_8K <= 11'd0;
            tiempo <= 1'b1;
        end
        
        if (rxf_245 == 1'b0 && rx_245 == 1'b1 && !haydato && !transmitiendo && tiempo && dato_leido) begin
            oe = 1'b0;              // Aseguro lectura del bus
            rx_245 <= 1'b0;         // Solicito el dato al FTDI
            wr_245 <= 1'b1;
        end
        else if (rxf_245 == 1'b0 && rx_245 == 1'b0 && !haydato && !transmitiendo && tiempo) begin
            dato_rx = in_out_245;       // Leo el dato (Bloqueante)
            llego_dato <= 1'b1;         // Aviso que hay dato recibido en dato_rx
            rx_245 <= 1'b1;
            tiempo <= 1'b0;
        end
        else if (dato_leido && llego_dato) begin
            llego_dato <= 1'b0;         // El dato recibido ya fue leido
        end
        else if (txe_245 == 1'b0 && haydato && !transmitiendo) begin
            oe = 1'b1;              // Aseguro escritura del bus
            dato_tx = dato;
            transmitiendo <= 1'b1;  // Flag de en transmisión
        end
        else if (transmitiendo && wr_245) begin
            wr_245 <= 1'b0;         // Solicito transmisión al FTDI
        end
        else if (transmitiendo&& !wr_245) begin
            wr_245 <= 1'b1;         // Cierro transmisión
            transmitiendo <= 1'b0;  // Bajo flag de en transmisión
            oe = 1'b0;              // Aseguro lectura del bus
        end
    end
    
    // Control de DAC
    always @ (posedge hwclk) begin
        nsync <= nsync;
        estado_dac <= estado_dac;
        sample_reg <= sample_reg;
        counter_bits <= counter_bits;
        if (reset) begin
            estado_dac <= ST_IDLE;
            dac_idle <= 1'b1;
            sample_reg <= 24'd0;
            counter_bits <= 0;
            nsync <= 1'b1;
        end
        else if (estado == 4'd10) begin
            case (estado_dac)
                ST_IDLE:
                begin
                    sample_reg <= 24'd0;
                    nsync <= 1'b1;
                    counter_bits <= 0;
                    counter_bclk <= 0;
                    if (muestra_lista) begin
                        sample_reg[15:0] <= muestra[15:0];
                        estado_dac <= ST_RUNNING;
                        dac_idle <= 1'b0;
                    end
                end
                
                ST_RUNNING:
                begin
                    nsync <= 1'b0;
                    
                    if (counter_bclk == PAM_CLKS_PER_BCLK/2) begin
                        bclk <= 0;
                        counter_bclk <= counter_bclk + 1;
                    end else if (counter_bclk == PAM_CLKS_PER_BCLK-1) begin
                        bclk <= 1;
                        sample_reg <= sample_reg << 1;
                        counter_bits <= counter_bits + 1;
                        counter_bclk <= 0;
                    end else begin
                        counter_bclk <= counter_bclk + 1;
                    end
                                        
                    if ((counter_bits == PAM_DATA_LENGHT-1) && (counter_bclk == PAM_CLKS_PER_BCLK-1)) begin
                        // Llegó al final del envio de una muestra
                        dac_idle <= 1'b1;
                        estado_dac <= ST_IDLE;
                    end
                end
                
                default:
                begin
                    estado_dac <= ST_IDLE;
                end
            endcase
        end
        else begin
            estado_dac <= ST_IDLE;
            sample_reg <= 24'd0;
            nsync <= 1'b1;
        end
    end
    
endmodule
