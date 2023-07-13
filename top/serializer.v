/* serializer.v V1 realiza varias tareas.
1. Espera recibir "UTN"
2. Luego envía "UTNv1\n"
3. Espera dos bytes que le indican el samp_rate
4. Luego envia "OK\n"
5 Lee constantemente la FIFO caracteres desde la PC a la tasa samp_rate*2 caracteres por segundo, puesto que una muestra son dos caracteres, de esta forma Mercurial (PF-2019) impone a GNU Radio el ritmo de funcionamiento.
Cada vez que obtiene una muestra se la pasa al DAC.

Significado de los leds
0 - Prende y Apaga cada un segundo
1 - Toggle cada vez que se recibe un dato o parte de la animación
2 - parte de la animación
3 - parte de la animación
4 - parte de la animación
5 - parte de la animación
6 - parte de la animación
7 - Apaga si está en estado operativo (recibió "UTN", envió UTNv1 entró en régimen)
*/

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
    output nsync               /*SYNC del AD5061*/
    );  

    /***************************************************************************
    * signals
    ****************************************************************************/

    reg clk;
    reg [3:0] estado = 4'b0;                      // estado indica en que estado está la placa
    reg rxf_245_reg;
    reg [7:0] dato_rx, dato_rx_reg, dato_tx_reg;
    reg rx_rq_reg;
    reg rx_st = 1'b0;
    reg tx_rq = 1'b0;
    reg tx_st_reg;
    reg alarma = 1'b1;
    reg [15:0] muestra = 16'd0;                   // El valor que va al DAC
    reg dac_rq = 1'b0;
    reg dac_st_reg;
    reg samp_rate_ant = 1'b0;
    reg [5:0] animacion;
    reg [11:0] WatchDog = 12'd4000;             // Desciende por cada muestra recibida
    reg [11:0] Ctn_anim = 12'd4000;             // Desciende por cada muestra recibida y se recarga
    reg medio_sg_ant = 1'b0;
    reg [1:0] gracia = 2'd2;                    // Cantidad de segundos antes de WatchDog operativo
    reg reset_sw = 1'b0;
    
    /***************************************************************************
     * assignments
     ***************************************************************************
     */
    assign clk = hwclk;
    assign reset_sgn = (reset_hw | reset_sw);
    assign rxf_245 = rxf_245_reg;
    assign leds[7] = alarma;
    assign leds[6:1] = animacion[5:0];
    assign pin_L23B = medio_sg;

    /***************************************************************************
     * module instances
     ****************************************************************************/
     
     temporizador temporizador(
        .clock_in   (clk),
        .reset_btn  (reset_btn),
        .medio_sg   (medio_sg),
        .rst_out    (reset_hw),
        .samp_rate  (samp_rate),
        .latido     (leds[0])
        );
        
     ftdi ftdi(
        .clock_in   (clk),
        .reset      (reset_sgn),
    
        .in_out_245 (in_out_245),   // Bus de datos con el FTDI
        .txe_245    (txe_245),      // Del FTDI, vale 0 si está disponible para transmitir a la PC
        .rxf_245_in    (rxf_245),   // Del FTDI, vale 0 cuando llegó un dato desde la PC
        .rx_245_out    (rx_245),    // Del FTDI, vale 0 para solicitar lectura de dato que llegó de la PC y lo toma en el flanco positivo
        .wr_245     (wr_245),       // Del FTDI, en el flanco descendente almacena el dato a transmitir a la PC
    
        .rx_data    (dato_rx),      // Dato recibido de la PC hacia Mercurial
        .rx_rq      (rx_rq),        // Alto para avisar a Mercurial que llegó un dato
        .rx_st      (rx_st),        // Flanco positivo cuando el dato fue leído por Mercurial

        .tx_data    (dato_tx_reg),  // Dato a transmitir a la PC desde Mercurial
        .tx_rq      (tx_rq),        // Alto para indicar que hay un dato desde Mercurial a transmitir
        .tx_st      (tx_st)         // Flanco positivo cuando el dato fue leído por este módulo
        
        );

    dac_spi dac_spi(
        .clock_in   (clk),
        .reset      (reset_sgn),
    
        .dac_data   (muestra),      // Muestra a convertir
        .dac_rq     (dac_rq),       // Alto para indicar que hay una muestra para convertir
        .dac_st     (dac_st),       // Vale cero si el DAC está disponible para nueva conversión

        .sdata      (sdata),
        .bclk       (bclk),
        .nsync      (nsync)         // SYNC del AD5061
        
    );
        
    /* always */
    /* Estados de la placa
    estado = 0 Inicio, espera "U"
    estado = 1 Recibió "U", espera "T"
    estado = 2 Recibió "T", espera "N"
    estado = 3 Envía "U"
    estado = 4 Envía "T"
    estado = 5 Envía "N"
    estado = 6 Envía "v"
    estado = 7 Envía "1"
    estado = 8 Envía "\n"
    estado = 9 Operativo recibe byte bajo
    estado = 10 Operativo recibe byte alto
    estado = 11 Operativo espera samp_rate
    estado = 12 Operativo Ordena conversión, WatchDog, Animación
    */
    always @ (posedge clk) begin
        rx_rq_reg <= rx_rq;
        tx_st_reg <= tx_st;
        dac_st_reg <= dac_st;
        // Si hubo reset vamos a estado = 0
        if (reset_sgn) begin
            rx_st <= 1'b0;
            tx_rq <= 1'b0;
            alarma <= 1'b1;
            reset_sw <= 1'b0;
            estado <= 4'd0;
        end
        // Analisis para pasar a estado 1
        else if (estado == 4'd0 && rx_rq_reg && !rx_st) begin
            dato_rx_reg <= dato_rx;
            rx_st <= 1'b1;
        end
        else if (estado == 4'd0 && !rx_rq_reg && rx_st) begin
            rx_st <= 1'b0;
            animacion[0] = ~animacion[0];
            // Si estoy en estado 0 y recibo "U", paso a estado 1
            estado = (dato_rx_reg == 8'd85) ? 4'd1 : 4'd0;
        end
        // Analisis para pasar a estado 2
        else if (estado == 4'd1 && rx_rq_reg && !rx_st) begin
            dato_rx_reg <= dato_rx;
            rx_st <= 1'b1;
        end
        else if (estado == 4'd1 && !rx_rq_reg && rx_st) begin
            rx_st <= 1'b0;
            animacion[0] = ~animacion[0];
            // Si estoy en estado 1 y recibo "T" paso a estado 2, si no vuelvo a estado 0
            estado = (dato_rx_reg == 8'd84) ? 4'd2 : 4'd0;
        end
        // Analisis para pasar a estado 3
        else if (estado == 4'd2 && rx_rq_reg && !rx_st) begin
            dato_rx_reg <= dato_rx;
            rx_st <= 1'b1;
        end
        else if (estado == 4'd2 && !rx_rq_reg && rx_st) begin
            rx_st <= 1'b0;
            animacion[0] = ~animacion[0];
            // Si estoy en estado 2 y recibo "N" paso a estado 3, si no vuelvo a estado 0
            estado = (dato_rx_reg == 8'd78) ? 4'd3 : 4'd0;
        end
        // Si estoy en estado 3, envío "U" y voy a estado 4
        else if (estado == 4'd3 && !tx_st_reg && !tx_rq) begin
            dato_tx_reg <= 8'd85;
            tx_rq <= 1'b1;
        end
        else if (estado == 4'd3 && tx_st_reg && tx_rq) begin
            tx_rq <= 1'b0;
            estado = 4'd4;
        end
        // Si estoy en estado 4, envío "T" y voy a estado 5
        else if (estado == 4'd4 && !tx_st_reg && !tx_rq) begin
            dato_tx_reg <= 8'd84;
            tx_rq <= 1'b1;
        end
        else if (estado == 4'd4 && tx_st_reg && tx_rq) begin
            tx_rq <= 1'b0;
            estado = 4'd5;
        end
        // Si estoy en estado 5, envío "N" y voy a estado 6
        else if (estado == 4'd5 && !tx_st_reg && !tx_rq) begin
            dato_tx_reg <= 8'd78;
            tx_rq <= 1'b1;
        end
        else if (estado == 4'd5 && tx_st_reg && tx_rq) begin
            tx_rq <= 1'b0;
            estado = 4'd6;
        end
        // Si estoy en estado 6, envío "v" y voy a estado 7
        else if (estado == 4'd6 && !tx_st_reg && !tx_rq) begin
            dato_tx_reg <= 8'd118;
            tx_rq <= 1'b1;
        end
        else if (estado == 4'd6 && tx_st_reg && tx_rq) begin
            tx_rq <= 1'b0;
            estado = 4'd7;
        end
        // Si estoy en estado 7, envío "1" y voy a estado 8
        else if (estado == 4'd7 && !tx_st_reg && !tx_rq) begin
            dato_tx_reg <= 8'd49;
            tx_rq <= 1'b1;
        end
        else if (estado == 4'd7 && tx_st_reg && tx_rq) begin
            tx_rq <= 1'b0;
            estado = 4'd8;
        end
        // Si estoy en estado 8, envío "\n" y voy a estado 9
        else if (estado == 4'd8 && !tx_st_reg && !tx_rq) begin
            dato_tx_reg <= 8'd10;
            tx_rq <= 1'b1;
        end
        else if (estado == 4'd8 && tx_st_reg && tx_rq) begin
            tx_rq <= 1'b0;
            // preparo las variables operativas
            alarma <= 1'b0;
            gracia <= 2'd2;
            WatchDog <= 12'd4000;
            Ctn_anim <= 12'd4000;
            animacion[5:0] <= 6'b1;
            // Próximo estado
            estado = 4'd9;
        end

        // Estado 9 entra operativo byte bajo
        else if (estado == 4'd9 && rx_rq_reg && !rx_st) begin
            dato_rx_reg <= dato_rx;
            rx_st <= 1'b1;
        end
        else if (estado == 4'd9 && !rx_rq_reg && rx_st) begin
            rx_st <= 1'b0;
            muestra[7:0] <= dato_rx_reg;
            estado = 4'd10;
        end
        
        // Estado 10 operativo byte alto
        else if (estado == 4'd10 && rx_rq_reg && !rx_st) begin
            dato_rx_reg <= dato_rx;
            rx_st <= 1'b1;
        end
        else if (estado == 4'd10 && !rx_rq_reg && rx_st) begin
            rx_st <= 1'b0;
            muestra[15:8] <= dato_rx_reg;
            estado = 4'd11;
        end

        // Estado 11 Detector de flanco ascendente de samp_rate
        if (estado == 4'd11 && samp_rate && !samp_rate_ant) begin
            estado = 4'd12;
        end
        
        // Estado 12 operativo ordena conversión, voy a estado 9
        else if (estado == 4'd12 && !dac_st_reg && !dac_rq) begin
            dac_rq <= 1'b1;
        end
        else if (estado == 4'd12 && dac_st_reg && dac_rq) begin
            dac_rq <= 1'b0;
            // Código para el WatchDog
            if (WatchDog != 12'd0) begin
                WatchDog <= WatchDog - 1;
            end
            // Código para animación
            Ctn_anim <= Ctn_anim - 1;
            if (Ctn_anim == 12'd0) begin
                animacion[5:0] <= (animacion[5]) ? 6'b1 : animacion[5:0] << 1;
                Ctn_anim <= 12'd4000;
            end
            // Próximo estado
            estado = 4'd9;
        end
        
        if (!medio_sg_ant && medio_sg && !alarma) begin
            // Detecto flanco ascendente de medio_sg (sucede entonces cada un segundo)
            if (gracia != 2'd0) begin
                gracia <= gracia -1;
            end
            else begin
                if (WatchDog == 12'd0) begin
                    WatchDog <= 12'd4000;
                end
                else begin
                    // Significa que no recibí muestras -> reset_sw
                    reset_sw <= 1'b1;
                end
            end
        end
        samp_rate_ant <= samp_rate; // Guardo el estado anterior de samp
        medio_sg_ant <= medio_sg;   // Guardo el estado para detectar flanco ascendente

    end

endmodule
