/* Prueba de recepción de caracteres desde la PC a una tasa comprometida de 8000 caracteres por segundo, impuesta por Mercurial.
Este códidgo lee del FTDI el dato que se envió desde la PC y lo almacena en dato_rx. 
La FIFO es bloqueante, es decir no admite otro dato de la PC si no se lee el anterior.

Significado de los leds
0 - Prende y Apaga cada un segundo
1 - Toggle cada vez que se recibe un dato
2 - Apagado significa que transmite un dato
3 - Apagado significa FTDI habilitado para transmitir 
4 - Se apaga cuando hay un dato para leer
5 - Sin asignar. Antes toggle cada vez que detecta un "0". Se prende si está en modo ECO
6 - Prende si recibió una "L"
7 - Prende si recibió una "H"
 
*/

/* module */
module top_module (
    /* I/O */
    input hwclk,
    inout [7:0] in_out_245,
    input txe_245,
    input rxf_245,
    output rx_245,
    output wr_245,
    output [7:0] leds,
    output pin_L23B);

    /* Counter register */
    /* hwclk: 12MHz -> max counter 12e6 */
    reg [25:0] counter = 26'b0;
    reg [10:0] counter_8K = 11'b0;
    reg [7:0] dato,dato_tx,dato_rx = 8'b0;
    reg haydato,transmitiendo,eco = 1'b0;
    reg oe = 1'b0;  // Output Enable
    reg tiempo = 1'b0;      // Para a uno cada 1/8000 Sg.
    
    assign in_out_245 = oe ? dato_tx : 8'bZ;
    //assign leds[5] = eco;
    assign pin_L23B = tiempo;

    /* always */
    always @ (posedge hwclk) begin
        counter <= counter + 1;
        leds[2] <= wr_245;
        leds[3] <= txe_245;
        leds[4] <= rxf_245;  // Se baja al recibir.

        // seconds counter
        if ( counter == 26'd6000000 )
        begin
            counter <= 26'd0;
            leds[0] <= ~leds[0];
        end

end

    // Evaluo si llegó un "0"
    always @ (posedge rxf_245) begin
        //if (dato_rx == 8'h30) begin // Si recibo "0" toggle eco y led[5]
            //eco <= ~eco;
        //end
        if (dato_rx == 8'd72) begin // Si recibo "H" prendo led leds[7]
            leds[7] <= 1;
            leds[6] <= 0;
        end
        else if (dato_rx == 8'd76) begin // Si recibo "L" prendo led leds[6]
            leds[7] <= 0;
            leds[6] <= 1;
        end
        else begin // Si recibo "L" prendo led leds[6]
            leds[7] <= 0;
            leds[6] <= 0;
        end
    end

    // llegó un dato
    always @ (posedge hwclk) begin
        counter_8K = tiempo ? counter_8K : counter_8K + 1;
        //counter_8K = counter_8K + 1;
        if ( counter_8K == 11'd1500 )
        begin
            counter_8K <= 11'd0;
            tiempo <= 1'b1;
            //pin_8K <= ~pin_8K;
        end
        if (rxf_245 == 1'b0 && rx_245 == 1'b1 && !haydato && !transmitiendo && tiempo) begin
            oe = 1'b0;              // Aseguro lectura del bus
            rx_245 <= 1'b0;         // Solicito el dato al FTDI
            wr_245 <= 1'b1;
        end
        else if (rxf_245 == 1'b0 && rx_245 == 1'b0 && !haydato && !transmitiendo && tiempo) begin
            dato_rx = in_out_245;      // Leo el dato (Bloqueante)
            rx_245 <= 1'b1;
            haydato = eco ? 1'b1 : 1'b0;        // Para bloquear la recepción
            transmitiendo <= 1'b0;  // Bajo flag de en transmisión
            leds[1] <= ~leds[1];
            tiempo <= 1'b0;
        end
        else if (txe_245 == 1'b0 && haydato && !transmitiendo) begin
            oe = 1'b1;              // Aseguro escritura del bus
            dato_tx = dato_rx;
            wr_245 <= 1'b0;         // Solicito transmisión al FTDI
            transmitiendo <= 1'b1;  // Flag de en transmisión
        end
        else if (transmitiendo) begin
            wr_245 <= 1'b1;         // Cierro transmisión
            haydato <= 1'b0;        // Para liberar recepción
            transmitiendo <= 1'b0;  // Bajo flag de en transmisión
            oe = 1'b0;              // Aseguro lectura del bus
        end
    end
    
endmodule
