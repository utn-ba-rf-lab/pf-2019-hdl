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
5 - Enciende si recibe "UT"
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
    output pin_8K);

    /* Counter register */
    /* hwclk: 12MHz -> max counter 12e6 */
    reg [25:0] counter = 26'b0;
    reg [10:0] counter_8K = 11'b0;
    reg [7:0] dato,dato_tx,dato_rx = 8'b0;
    reg haydato,transmitiendo,eco = 1'b0;
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
    //assign leds[5] = eco;
    assign pin_8K = tiempo;

    /* always */
    always @ (posedge hwclk) begin
        counter <= counter + 1;
        leds[2] <= ~wr_245;
        leds[3] <= txe_245;
        leds[4] <= rxf_245;  // Se baja al recibir.

        // seconds counter
        if ( counter == 26'd6000000 )
        begin
            counter <= 26'd0;
            leds[0] <= ~leds[0];
        end

end

    // Entra si llegó un dato 
    always @ (posedge rxf_245) begin
        // Si estoy en estado 0 y recibo "U", paso a estado 1
        if (dato_rx == 8'd85 && estado == 0) begin 
            estado <= 1;
        end
        // Si estoy en estado 1 y recibo "T", paso a estado 2 y prendo led[5]
        else if (dato_rx == 8'd84 && estado == 1) begin 
            estado <= 2;
        end
        // Si estoy en estado 2 y recibo "N", paso a estado 3 y prendo led[5]
        else if (dato_rx == 8'd78 && estado == 2) begin 
            leds[5] <= 1;
            estado <= 3;
        end
        else if (dato_rx == 8'd72) begin // Si recibo "H" prendo led leds[7]
            leds[7] <= 1;
            leds[6] <= 0;
        end
        else if (dato_rx == 8'd76) begin // Si recibo "L" prendo led leds[6]
            leds[7] <= 0;
            leds[6] <= 1;
        end
        else begin // Si no es ni "H" ni "L" apago leds
            leds[7] <= 0;
            leds[6] <= 0;
            estado <= 0;
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
