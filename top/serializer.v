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

/* module */
module top_module (
    /* Base de tiempos */
    input hwclk,                /*Clock*/
    input reset_btn,            /*Botón de reset*/
    );
    
    reg [25:0] counter = 26'b0;     // Counter register - hwclk: 12MHz -> max counter 12e6
    reg reset = 1'b0;               // Vale 1 si hubo reset por 100 uSg
    reg a1 = 1'b0;                  // Toggle Cada medio segundo por un ciclo de clock

    /* always */
    always @ (posedge hwclk) begin
        reset <= reset;
        a1 <= a1;
        counter <= counter + 1;
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
endmodule
