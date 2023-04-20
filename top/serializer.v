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
5 - Enciende si recibe "UTN"
6 - Prende si recibió una "L"
7 - Prende si recibió una "H"
 
*/

/* module */
module top_module (
    /* I/O */
    input hwclk,
    input reset_btn,
    inout [7:0] in_out_245,
    input txe_245,
    input rxf_245,
    output rx_245,
    output wr_245,
    output [7:0] leds,
    output pin_8K);

    /* Counter register */
    /* hwclk: 12MHz -> max counter 12e6 */
    reg [25:0] counter = 26'b0;
    reg [10:0] counter_8K = 11'b0;
    reg [7:0] dato,dato_tx,dato_rx = 8'b0;
    reg haydato,transmitiendo,reset,llego_dato = 1'b0;
    reg dato_leido = 1'b1;
    reg oe = 1'b0;  // Output Enable
    reg tiempo = 1'b0;      // Pasa a uno cada 1/8000 Sg.
    reg [3:0] estado = 4'b0;      // estado indica en que estado está la placa
/*
estado = 0 Inicio, espera "U"
estado = 1 Recibió "U", espera "T"
estado = 2 Recibió "T", espera "N"
estado = 3 Envia "U"
estado = 4 Envia "T"
estado = 5 Envia "N"
estado = 6 Envia "v"
estado = 7 Envia "1"
estado = 8 Detector
*/
    
    assign in_out_245 = oe ? dato_tx : 8'bZ;
    assign pin_8K = tiempo;

    /* always */
    always @ (posedge hwclk) begin
        reset <= reset;
        counter <= counter + 1;
        leds[2] <= ~wr_245;
        leds[3] <= txe_245;
        leds[4] <= rxf_245;  // Se baja al recibir.
        
        // ¿Botón de reset oprimido?
        if (reset_btn && !reset) begin
            counter <= 26'd0;
            leds[0] <= 1'b0;
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
            leds[0] <= ~leds[0];
        end

    end
    
    // Máquina de estados
    always @ (posedge hwclk) begin
        estado <= estado;
        if (reset) 
            estado <= 4'd0;
        else if (llego_dato) begin
            case (estado)
                // Si estoy en estado 0 y recibo "U", paso a estado 1
                4'd0 : estado = (dato_rx == 8'd85) ? 4'd1 : 4'd0;
                // Si estoy en estado 1 y recibo "T", paso a estado 2
                4'd1 : estado = (dato_rx == 8'd84) ? 4'd2 : 4'd0;
                // Si estoy en estado 2 y recibo "N", paso a estado 3
                4'd2 : estado = (dato_rx == 8'd78) ? 4'd3 : 4'd0;
            endcase
        end
        else if (haydato && !transmitiendo) begin
            case (estado)
                // Si estoy en estado 3, paso a estado 4 y así sucesivamente
                4'd3 : estado <= 4'd4;
                4'd4 : estado <= 4'd5;
                4'd5 : estado <= 4'd6;
                4'd6 : estado <= 4'd7;
                4'd7 : estado <= 4'd8;
            endcase
        end
    end

    // Lógica de serializer
    always @ (posedge hwclk) begin
        if (estado == 4'd0) begin
            leds[5] <= 0;
            leds[7] <= 0;
            leds[6] <= 0;
            haydato <= 1'b0;
        end
        else if (estado == 4'd3) begin
            leds[5] <= 1;
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
            haydato <= 1'b0;
            case (dato_rx)
                // Si recibo "H" prendo led leds[7]
                8'd72 : begin // Si recibo "H" prendo led leds[7]
                leds[7] <= 1;
                leds[6] <= 0;
                end 
                // Si recibo "L" prendo led leds[6]
                8'd76 : begin // Si recibo "L" prendo led leds[6]
                leds[7] <= 0;
                leds[6] <= 1;
                end 
                // Si recibo otro apago leds 6 y 7 
                default : begin 
                leds[7] <= 0;
                leds[6] <= 0;
                end 
            endcase
        end
    end

    // Evalua estado del FTDI
    always @ (posedge hwclk) begin
        counter_8K = tiempo ? counter_8K : counter_8K + 1;
        //counter_8K = counter_8K + 1;
        if ( counter_8K == 11'd1500 )
        begin
            counter_8K <= 11'd0;
            tiempo <= 1'b1;
            //pin_8K <= ~pin_8K;
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
            //transmitiendo <= 1'b0;  // ¿Esto tiene sentido aquí?
            leds[1] <= ~leds[1];
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
    
endmodule
