/* serializer.v V" realiza varias tareas.
1. Espera recibir "UTN"
2. Luego envía "UTNv2\n"
3. Espera dos bytes que le indican el samp_rate
4. Luego envia "OK\n"
5 Lee constantemente la FIFO caracteres desde la PC a la tasa samp_rate*2 caracteres por segundo, puesto que una muestra son dos caracteres, de esta forma Mercurial (PF-2019) impone a GNU Radio el ritmo de funcionamiento.
Cada vez que obtiene una muestra se la pasa al DAC.

Significado de los leds
0 - Prende y Apaga cada un segundo
1 - Toggle cada vez que se recibe un dato [Próximamente]
2 - Sin asignar
3 - Sin asignar
4 - Sin asignar
5 - Sin asignar
6 - Sin asignar
7 - Apaga si está en estado operativo (recibió "UTN", envió UTNv1 entró en régimen) [Próximamente]
 
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
     ***************************************************************************
     */
    reg clk;
    reg [7:0] led_reg;
    reg [3:0] estado = 4'b0;                    // estado indica en que estado está la placa
    reg rxf_245_reg;
    reg [7:0] dato_rx, dato_rx_reg, dato_tx_reg;
    reg rx_rq_reg;
    reg rx_st = 1'b0;
    reg tx_rq = 1'b0;
    reg tx_st_reg;
    
    /***************************************************************************
     * assignments
     ***************************************************************************
     */
    assign clk = hwclk;
    //assign leds = led_reg;
    assign rxf_245 = rxf_245_reg;
    assign leds[4] = rx_rq_reg;

    /***************************************************************************
     * module instances
     ***************************************************************************
     */
     temporizador temporizador(
        .clock_in   (clk),
        .reset_btn  (reset_btn),
        .medio_sg   (medio_sg),
        .rst_out    (reset_sgn),
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
        .tx_st      (tx_st),        // Flanco positivo cuando el dato fue leído por este módulo
        
        .test1      (leds[2]),
        .test2      (leds[3]),
        .test3      (pin_L23B)
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
    estado = 9 Detector sin WatchDog
    estado = 10 Detector con WatchDog
    */
    always @ (posedge clk) begin
        rx_rq_reg <= rx_rq;
        tx_st_reg <= tx_st;
        // Si hubo reset vamos a estado = 0
        if (reset_sgn) begin
            //samp_rate_error <= 1'b0;
            rx_st <= 1'b0;
            tx_rq <= 1'b0;
            leds[7] = 1'b0;
            estado <= 4'd0;
        end
        // Analisis para pasar a estado 1
        else if (estado == 4'd0 && rx_rq_reg && !rx_st) begin
            dato_rx_reg <= dato_rx;
            rx_st <= 1'b1;
        end
        else if (estado == 4'd0 && !rx_rq_reg && rx_st) begin
            rx_st <= 1'b0;
            leds[1] = ~leds[1];
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
            leds[1] = ~leds[1];
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
            leds[1] = ~leds[1];
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
            estado = 4'd9;
            leds[7] = 1'b1;
        end
        // Estado 9 (Proximamente) Por ahora recibe y tira.
        else if (estado == 4'd9 && rx_rq_reg && !rx_st) begin
            dato_rx_reg <= dato_rx;
            rx_st <= 1'b1;
        end
        else if (estado == 4'd9 && !rx_rq_reg && rx_st) begin
            rx_st <= 1'b0;
            leds[1] = ~leds[1];
            // Analizar lo recibido
        end
        
    end

endmodule
