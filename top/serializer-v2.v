/* serializer.v V2 realiza varias tareas.
1. Espera recibir "UTN"
2. Luego envía "UTNv2\n"
3. Espera dos bytes que le indican el samp_rate
4. Luego envia "OK\n"
5 Lee constantemente la FIFO caracteres desde la PC a la tasa samp_rate*2 caracteres (muestras) por segundo, puesto que una muestra son dos caracteres, de esta forma Mercurial (PF-2019) impone a GNU Radio el ritmo de funcionamiento.
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
    reg [4:0] estado = 5'b0;                      // estado indica en que estado está la placa
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
    reg tiempo_ant = 1'b0;
    reg [5:0] animacion;
    reg [11:0] WatchDog = 12'd4000;             // Desciende por cada muestra recibida
    reg [11:0] Ctn_anim = 12'd4000;             // Desciende por cada muestra recibida y se recarga
    reg medio_sg_ant = 1'b0;
    reg [1:0] gracia = 2'd2;                    // Cantidad de segundos antes de WatchDog operativo
    reg reset_sw = 1'b0;
    reg [7:0] tiempos;                          // 48, 44.1, 32, 24, 22.05, 16, 11.025, 8 KHz
    reg [2:0] tiempo_sel = 3'd0;                // Tasa de muestra seleccionada
    reg [15:0] samp_rate = 16'd0;               // samp_rate recibido de gr-serializer
    
    /***************************************************************************
     * assignments
     ***************************************************************************
     */
    assign clk = hwclk;
    assign reset_sgn = (reset_hw | reset_sw);
    assign rxf_245 = rxf_245_reg;
    assign leds[7] = alarma;
    assign leds[6:1] = animacion[5:0];
    assign pin_L23B = tiempo;
    assign pin_L4B = (estado == 5'd17);         // Pasa a alto si está esperando para convertir (Idle)
    assign tiempo = tiempos[tiempo_sel];

    /***************************************************************************
     * module instances
     ****************************************************************************/
     
     temporizador temporizador(
        .clock_in   (clk),
        .reset_btn  (reset_btn),
        .medio_sg   (medio_sg),
        .rst_out    (reset_hw),
        .samp_rates  (tiempos),
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
    estado = 0 Inicio, espera "U", si no va estado 0
    estado = 1 Recibió "U" espera "T", si no va estado 0
    estado = 2 Recibió "T" espera "N", si no va estado 0
    estado = 3 Envía "U"
    estado = 4 Envía "T"
    estado = 5 Envía "N"
    estado = 6 Envía "v"
    estado = 7 Envía "2"
    estado = 8 Envía "\n"
    estado = 9 Recibe samp_rate bajo
    estado = 10 Recibe samp_rate alto, va estado 11
    estado = 11 Determina tiempo_sel en base a samp_rate para operar, va estados 12 o 19
    estado = 12 Envía "O"
    estado = 13 Envía "K"
    estado = 14 Envía "\n", ajusta variables de operación
    estado = 15 Operativo recibe byte bajo
    estado = 16 Operativo recibe byte alto
    estado = 17 Operativo espera tiempo de muestra
    estado = 18 Operativo Ordena conversión, WatchDog, Animación, va estado 14
    estado = 19 Envía "E"
    estado = 20 Envía "R"
    estado = 21 Envía "R"
    estado = 22 Envía "O"
    estado = 23 Envía "R"
    estado = 24 Envía "\n", va estado 0
    */
    always @ (posedge clk) begin
        rx_rq_reg <= rx_rq;
        tx_st_reg <= tx_st;
        dac_st_reg <= dac_st;
        // Si hubo reset vamos a estado = 0
        if (reset_sgn) begin
            rx_st <= 1'b0;
            tx_rq <= 1'b0;
            animacion[5:0] <= 6'b0;
            alarma <= 1'b1;
            reset_sw <= 1'b0;
            tiempo_sel <= 3'd0;
            estado <= 5'd0;
        end

        // Analisis para pasar a estado 1
        else if (estado == 5'd0 && rx_rq_reg && !rx_st) begin
            dato_rx_reg <= dato_rx;
            rx_st <= 1'b1;
        end
        else if (estado == 5'd0 && !rx_rq_reg && rx_st) begin
            rx_st <= 1'b0;
            animacion[0] = ~animacion[0];
            tiempo_sel <= 3'd0;
            // Si estoy en estado 0 y recibo "U", paso a estado 1
            estado = (dato_rx_reg == 8'd85) ? 5'd1 : 5'd0;
        end

        // Estado 1, analisis para pasar a estado 2
        else if (estado == 5'd1 && rx_rq_reg && !rx_st) begin
            dato_rx_reg <= dato_rx;
            rx_st <= 1'b1;
        end
        else if (estado == 5'd1 && !rx_rq_reg && rx_st) begin
            rx_st <= 1'b0;
            animacion[0] = ~animacion[0];
            // Si estoy en estado 1 y recibo "T" paso a estado 2, si no vuelvo a estado 0
            estado = (dato_rx_reg == 8'd84) ? 5'd2 : 5'd0;
        end

        // Analisis para pasar a estado 3
        else if (estado == 5'd2 && rx_rq_reg && !rx_st) begin
            dato_rx_reg <= dato_rx;
            rx_st <= 1'b1;
        end
        else if (estado == 5'd2 && !rx_rq_reg && rx_st) begin
            rx_st <= 1'b0;
            animacion[0] = ~animacion[0];
            // Si estoy en estado 2 y recibo "N" paso a estado 3, si no vuelvo a estado 0
            estado = (dato_rx_reg == 8'd78) ? 5'd3 : 5'd0;
        end

        // Si estoy en estado 3, envío "U" y voy a estado 4
        else if (estado == 5'd3 && !tx_st_reg && !tx_rq) begin
            dato_tx_reg <= 8'd85;
            tx_rq <= 1'b1;
        end
        else if (estado == 5'd3 && tx_st_reg && tx_rq) begin
            tx_rq <= 1'b0;
            estado = 5'd4;
        end

        // Si estoy en estado 4, envío "T" y voy a estado 5
        else if (estado == 5'd4 && !tx_st_reg && !tx_rq) begin
            dato_tx_reg <= 8'd84;
            tx_rq <= 1'b1;
        end
        else if (estado == 5'd4 && tx_st_reg && tx_rq) begin
            tx_rq <= 1'b0;
            estado = 5'd5;
        end

        // Si estoy en estado 5, envío "N" y voy a estado 6
        else if (estado == 5'd5 && !tx_st_reg && !tx_rq) begin
            dato_tx_reg <= 8'd78;
            tx_rq <= 1'b1;
        end
        else if (estado == 5'd5 && tx_st_reg && tx_rq) begin
            tx_rq <= 1'b0;
            estado = 5'd6;
        end

        // Si estoy en estado 6, envío "v" y voy a estado 7
        else if (estado == 5'd6 && !tx_st_reg && !tx_rq) begin
            dato_tx_reg <= 8'd118;
            tx_rq <= 1'b1;
        end
        else if (estado == 5'd6 && tx_st_reg && tx_rq) begin
            tx_rq <= 1'b0;
            estado = 5'd7;
        end

        // Si estoy en estado 7, envío "2" y voy a estado 8
        else if (estado == 5'd7 && !tx_st_reg && !tx_rq) begin
            dato_tx_reg <= 8'd50;
            tx_rq <= 1'b1;
        end
        else if (estado == 5'd7 && tx_st_reg && tx_rq) begin
            tx_rq <= 1'b0;
            estado = 5'd8;
        end

        // Si estoy en estado 8, envío "\n" y voy a estado 9
        else if (estado == 5'd8 && !tx_st_reg && !tx_rq) begin
            dato_tx_reg <= 8'd10;
            tx_rq <= 1'b1;
        end
        else if (estado == 5'd8 && tx_st_reg && tx_rq) begin
            tx_rq <= 1'b0;
            // Próximo estado
            estado = 5'd9;
        end

        // Estado 9, recibe samp_rate bajo
        else if (estado == 5'd9 && rx_rq_reg && !rx_st) begin
            dato_rx_reg <= dato_rx;
            rx_st <= 1'b1;
        end
        else if (estado == 5'd9 && !rx_rq_reg && rx_st) begin
            rx_st <= 1'b0;
            animacion[0] = ~animacion[0];
            samp_rate[7:0] <= dato_rx_reg;
            // Próximo estado
            estado = 5'd10;
        end
                
        // Estado 10, recibe samp_rate alto, va estado 11
        else if (estado == 5'd10 && rx_rq_reg && !rx_st) begin
            dato_rx_reg <= dato_rx;
            rx_st <= 1'b1;
        end
        else if (estado == 5'd10 && !rx_rq_reg && rx_st) begin
            rx_st <= 1'b0;
            animacion[0] = ~animacion[0];
            samp_rate[15:8] <= dato_rx_reg;
            // Próximo estado
            estado = 5'd11;
        end
        
        // Estado 11,  Determina tiempo_sel en base a samp_rate para operar y va estados 12 o 19
        else if (estado == 5'd11) begin
            case (samp_rate)
                16'd8000:
                begin
                    tiempo_sel <= 3'd0;
                    estado = 5'd12;
                end
                
                16'd11025:
                begin
                    tiempo_sel <= 3'd1;
                    estado = 5'd12;
                end
                
                16'd16000:
                begin
                    tiempo_sel <= 3'd2;
                    estado = 5'd12;
                end
                
                16'd22050:
                begin
                    tiempo_sel <= 3'd3;
                    estado = 5'd12;
                end
                
                16'd24000:
                begin
                    tiempo_sel <= 3'd4;
                    estado = 5'd12;
                end
                
                16'd32000:
                begin
                    tiempo_sel <= 3'd5;
                    estado = 5'd12;
                end
                
                16'd44100:
                begin
                    tiempo_sel <= 3'd6;
                    estado = 5'd12;
                end

                16'd48000:
                begin
                    tiempo_sel <= 3'd7;
                    estado = 5'd12;
                end

                16'd0:
                begin
                    estado = 5'd12;         // Modo best efforts (tiempo_sel no importa)
                end

                default:
                begin
                    estado = 5'd19;         // No encontré un samp_rate válido informo ERROR
                end
            endcase
        end
        
        // Estado 12, Envía "O" y voy a estado 13
        else if (estado == 5'd12 && !tx_st_reg && !tx_rq) begin
            dato_tx_reg <= 8'd79;
            tx_rq <= 1'b1;
        end
        else if (estado == 5'd12 && tx_st_reg && tx_rq) begin
            tx_rq <= 1'b0;
            // Próximo estado
            estado = 5'd13;
        end

        // Estado 13, Envía "K" y voy a estado 14
        else if (estado == 5'd13 && !tx_st_reg && !tx_rq) begin
            dato_tx_reg <= 8'd75;
            tx_rq <= 1'b1;
        end
        else if (estado == 5'd13 && tx_st_reg && tx_rq) begin
            tx_rq <= 1'b0;
            // Próximo estado
            estado = 5'd14;
        end

        // Estado 14, Envía "\n", ajusta variables de operación y voy a estado 15
        else if (estado == 5'd14 && !tx_st_reg && !tx_rq) begin
            dato_tx_reg <= 8'd10;
            tx_rq <= 1'b1;
        end
        else if (estado == 5'd14 && tx_st_reg && tx_rq) begin
            tx_rq <= 1'b0;
            // Ajusta variables de operación
            alarma <= 1'b0;
            gracia <= 2'd2;
            WatchDog <= 12'd4000;
            Ctn_anim <= 12'd4000;
            animacion[5:0] <= 6'b1;
            // Próximo estado
            estado = 5'd15;
        end
        
        // Estado 15 entra operativo, recibe byte bajo, va estado 16
        else if (estado == 5'd15 && rx_rq_reg && !rx_st) begin
            dato_rx_reg <= dato_rx;
            rx_st <= 1'b1;
        end
        else if (estado == 5'd15 && !rx_rq_reg && rx_st) begin
            rx_st <= 1'b0;
            muestra[7:0] <= dato_rx_reg;
            // Próximo estado
            estado = 5'd16;
        end
        
        // Estado 16 operativo, recibe byte alto, va estado 17 o 18 si está en best efforts
        else if (estado == 5'd16 && rx_rq_reg && !rx_st) begin
            dato_rx_reg <= dato_rx;
            rx_st <= 1'b1;
        end
        else if (estado == 5'd16 && !rx_rq_reg && rx_st) begin
            rx_st <= 1'b0;
            muestra[15:8] <= dato_rx_reg;
            // Próximo estado
            estado <= (samp_rate == 16'd0) ? 5'd18 : 5'd17;
        end

        // Estado 17 Detector de flanco ascendente de tiempo luego va a estado 17
        if (estado == 5'd17 && tiempo && !tiempo_ant) begin
            estado = 5'd18;
        end
        
        // Estado 18 Ordena conversión, WatchDog, Animación, va estado 15
        else if (estado == 5'd18 && !dac_st_reg && !dac_rq) begin
            dac_rq <= 1'b1;
        end
        else if (estado == 5'd18 && dac_st_reg && dac_rq) begin
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
            estado = 5'd15;
        end

        // Estado 19, Envía "E" y voy a estado 20
        else if (estado == 5'd19 && !tx_st_reg && !tx_rq) begin
            dato_tx_reg <= 8'd69;
            tx_rq <= 1'b1;
        end
        else if (estado == 5'd19 && tx_st_reg && tx_rq) begin
            tx_rq <= 1'b0;
            // Próximo estado
            estado = 5'd20;
        end

        // Estado 20, Envía "R" y voy a estado 21
        else if (estado == 5'd20 && !tx_st_reg && !tx_rq) begin
            dato_tx_reg <= 8'd82;
            tx_rq <= 1'b1;
        end
        else if (estado == 5'd20 && tx_st_reg && tx_rq) begin
            tx_rq <= 1'b0;
            // Próximo estado
            estado = 5'd21;
        end

        // Estado 21, Envía "R" y voy a estado 22
        else if (estado == 5'd21 && !tx_st_reg && !tx_rq) begin
            dato_tx_reg <= 8'd82;
            tx_rq <= 1'b1;
        end
        else if (estado == 5'd21 && tx_st_reg && tx_rq) begin
            tx_rq <= 1'b0;
            // Próximo estado
            estado = 5'd22;
        end

        // Estado 22, Envía "O" y voy a estado 23
        else if (estado == 5'd22 && !tx_st_reg && !tx_rq) begin
            dato_tx_reg <= 8'd79;
            tx_rq <= 1'b1;
        end
        else if (estado == 5'd22 && tx_st_reg && tx_rq) begin
            tx_rq <= 1'b0;
            // Próximo estado
            estado = 5'd23;
        end

        // Estado 23, Envía "R" y voy a estado 24
        else if (estado == 5'd23 && !tx_st_reg && !tx_rq) begin
            dato_tx_reg <= 8'd82;
            tx_rq <= 1'b1;
        end
        else if (estado == 5'd23 && tx_st_reg && tx_rq) begin
            tx_rq <= 1'b0;
            // Próximo estado
            estado = 5'd24;
        end

        // Estado 24, Envía "\n", voy a estado 0
        else if (estado == 5'd24 && !tx_st_reg && !tx_rq) begin
            dato_tx_reg <= 8'd10;
            tx_rq <= 1'b1;
        end
        else if (estado == 5'd24 && tx_st_reg && tx_rq) begin
            tx_rq <= 1'b0;
            // Próximo estado
            estado = 5'd0;
        end
        
        //*** Evaluación del WatchDog
        
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
        
        tiempo_ant <= tiempo; // Guardo el estado anterior de samp
        medio_sg_ant <= medio_sg;   // Guardo el estado para detectar flanco ascendente

    end

endmodule
