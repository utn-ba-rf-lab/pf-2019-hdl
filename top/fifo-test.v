/* Prueba de envio de caracter desde la PC a la FIFO de pf-2019
Este códidgo lee del FTDI el dato que se envió desde la PC y lo almacena en dato_rx. 
La FIFO es bloqueante, es decir no admite otro dato de la PC si no se lee el anterior.
Si recibe un "0" se habilita o se dehabilita el eco, es decir el dato recibo es transmitido a la PC.

Significado de los leds
0 - Prende y Apaga cada un segundo
1 - Toggle cada vez que se recibe un dato
2 - Apagado significa que transmite un dato
3 - Apagado significa FTDI habilitado para transmitir 
4 - Se apaga cuando hay un dato para leer
5 - Toggle cada vez que detecta un "0". Se prende si está en modo ECO
6 - Dato[1]
7 - Dato[0]
 
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
    output [7:0] leds );

    /* Counter register */
    /* hwclk: 12MHz -> max counter 12e6 */
    reg [25:0] counter = 26'b0;
    reg [7:0] dato,dato_tx,dato_rx = 8'b0;
    reg haydato,transmitiendo,eco = 1'b0;
    reg oe = 1'b0;  // Output Enable 
    
    assign in_out_245 = oe ? dato_tx : 8'bZ;
    assign leds[5] = eco;

    /* always */
    always @ (posedge hwclk) begin
        counter <= counter + 1;
        leds[2] <= wr_245;
        leds[3] <= txe_245;
        leds[4] <= rxf_245;  // Se baja al recibir.
        //leds[5] <= dato[2];
        leds[6] <= dato_rx[1];
        leds[7] <= dato_rx[0];

        // second counter
        if ( counter == 26'd6000000 )
        begin
            counter <= 26'd0;
            leds[0] <= ~leds[0];
        end
    end

    // Evaluo si llegó un "0"
    always @ (posedge rxf_245) begin
        if (dato_rx == 8'h30) begin // Si recibo "0" toggle eco y led[5]
            eco <= ~eco;
        end
        //else 
            //eco <= 1'b0;
    end

    // llegó un dato
    always @ (posedge hwclk) begin
        if (rxf_245 == 1'b0 && rx_245 == 1'b1 && !haydato && !transmitiendo) begin
            oe = 1'b0;              // Aseguro lectura del bus
            rx_245 <= 1'b0;         // Solicito el dato al FTDI
            wr_245 <= 1'b1;
        end
        else if (rxf_245 == 1'b0 && rx_245 == 1'b0 && !haydato && !transmitiendo) begin
            dato_rx = in_out_245;      // Leo el dato (Bloqueante)
            rx_245 <= 1'b1;
            haydato = eco ? 1'b1 : 1'b0;        // Para bloquear la recepción
            transmitiendo <= 1'b0;  // Bajo flag de en transmisión
            leds[1] <= ~leds[1];
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
