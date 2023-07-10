module ftdi(
    input   clock_in,
    input   reset,
    
    inout [7:0] in_out_245,     // Bus de datos con el FTDI
    input   txe_245,            // Del FTDI, vale 0 si está disponible para transmitir a la PC
    input   rxf_245_in,         // Del FTDI, vale 0 cuando llegó un dato desde la PC
    output  rx_245_out,         // Del FTDI, vale 0 para solicitar lectura de dato que llegó de la PC y lo toma en el flanco positivo
    output  wr_245,             // Del FTDI, en el flanco descendente almacena el dato a transmitir a la PC
    
    output [7:0] rx_data,       // Dato recibido de la PC hacia Mercurial
    output  rx_rq,              // Alto para avisar a Mercurial que llegó un dato
    input   rx_st,              // Flanco positivo cuando el dato fue leído por Mercurial

    input [7:0] tx_data,        // Dato a transmitir a la PC desde Mercurial
    input   tx_rq,              // Alto para indicar que hay un dato desde Mercurial a transmitir
    output  tx_st               // Flanco positivo cuando el dato fue leído por este módulo
    
    );

    reg [2:0] estado_ftdi_rx = 3'd0;
    reg [2:0] estado_ftdi_tx = 3'd0;
    reg txe_245_reg;
    reg rxf_245_reg = 1'b1;
    reg rx_rq;
    reg rx_st_reg;
    reg tx_rq_reg;
    reg tx_st;
    //reg rx_245_reg = 1'b1;
    reg [7:0] tx_data_in;
    reg oe = 1'b0;              // Output Enable
    //reg transmitiendo = 1'b0;

    /***************************************************************************
     * assignments
     ***************************************************************************
     */
    assign in_out_245 = oe ? tx_data_in : 8'bZ;

    /* Estados de estado_ftdi_rx
    estado = 0 Idle
    voy a estado = 1 si Recibió un caracter por USB y le pidió a FTDI que lo vuelque
    voy a estado = 2 si Tomó el dato lo puso en rx_data
    voy a estado = 3 si Aviso a modulo top del dato arrivado
    voy a estado = 4 si el Dato es tomado por modulo top
    estado = 5 Modulo top libera bus
    
    Estados de estado_ftdi_tx
    estado = 0 Idle
    voy a estado = 1 si Recibió un caracter por módulo top y levantó tx_rq
    voy a estado = 2 si Tomó el dato en tx_data y lo almacena en tx_data_in
    voy a estado = 3 si Aviso a modulo top de la toma del dato subiendo tx_st
    voy a estado = 4 si el modulo top baja tx_rq
    voy a estado = 0 bajo tx_st
    */

    always @ (posedge clock_in) begin
        txe_245_reg <= txe_245;
        rxf_245_reg <= rxf_245_in;
        rx_st_reg <= rx_st;
        tx_rq_reg <= tx_rq;
        
        // Si hubo reset vamos a estado Idle
        if (reset) begin
            estado_ftdi_rx <= 3'd0;
            estado_ftdi_tx <= 3'd0;
            rx_rq <= 1'b0;
            tx_st <= 1'b0;
            oe = 1'b0;
            wr_245 = 1'b1;
        end

        else if (estado_ftdi_rx == 3'd0 && estado_ftdi_tx == 3'd0) begin
            // Si estoy ocioso indago si hay algo para transmitir en Mercurial y si lo puedo enviar
            if (tx_rq_reg && !txe_245_reg) begin
                // Si recibí un caracter de percurial se lo mando a la FTDI
                oe = 1'b1;              // Aseguro escritura del bus
                wr_245 <= 1'b1;
                estado_ftdi_tx <= 3'd1; //
            end
            // Si estoy ocioso indago si recibí algo en el FTDI
            else if (!rxf_245_reg) begin
                // Si recibí un caracter por el FTDI lo leo
                oe = 1'b0;              // Aseguro lectura del bus
                rx_245_out <= 1'b0;     // Solicito el dato al FTDI
                estado_ftdi_rx <= 3'd1; //
            end
        end

        // Aqui comienzan los estados para la transmisión a la PC
        else if (estado_ftdi_tx == 3'd1) begin
            tx_data_in <= tx_data;
            //tx_data_in <= 8'd85;
            tx_st <= 1'b1;
            estado_ftdi_tx <= 3'd2;
        end
        else if (estado_ftdi_tx == 3'd2) begin
            wr_245 <= 1'b0;
            estado_ftdi_tx <= 3'd3;
        end
        else if (estado_ftdi_tx == 3'd3) begin
            wr_245 <= 1'b1;
            tx_st <= 1'b0;
            estado_ftdi_tx <= 3'd4;
        end
        else if (estado_ftdi_tx == 3'd4 && !tx_rq_reg) begin
            estado_ftdi_tx <= 3'd0;
        end

        // Aqui comienzan los estados para la lectura del FDTI y entrega a Mercurial
        else if (estado_ftdi_rx == 3'd1) begin
            rx_data = in_out_245;    // Leo el dato (Bloqueante)
            rx_245_out <= 1'b1;      // Flanco de lectura
            estado_ftdi_rx <= 3'd2;
        end
        else if (estado_ftdi_rx == 3'd2) begin
            rx_rq <= 1'b1;
            estado_ftdi_rx <= 3'd3;
        end
        else if (estado_ftdi_rx == 3'd3 && rx_st_reg == 1'b1) begin
            rx_rq <= 1'b0;
            estado_ftdi_rx <= 3'd4;
        end
        else if (estado_ftdi_rx == 3'd4 && rx_st_reg == 1'b0) begin
            estado_ftdi_rx <= 3'd0;
        end
    end    

endmodule
