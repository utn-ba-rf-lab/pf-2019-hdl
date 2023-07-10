module temporizador(
    input  clock_in,
    input  reset_btn,
    output medio_sg,		// Toggle cada medio segundo
    output rst_out,		// Vale 1 si hubo reset por 100 uSg desde que suelto el botón
    output samp_rate,           // 8 KHz
    output latido		// Prende por 100 mSg cada segundo
    );

    reg [25:0] counter = 26'b0;     // Counter register - hwclk: 12MHz -> max counter 12e6
    reg [9:0] counter8K = 10'd750;  // Counter register 8KSpS
    reg medio_sg_reg = 1'b0;
    reg rst_out_reg = 1'b0;

    /***************************************************************************
     * assignments
     ***************************************************************************
     */
    assign medio_sg = medio_sg_reg;
    assign rst_out = rst_out_reg;

    always @ (posedge clock_in) begin
        counter <= counter + 1;
        // ¿Botón de reset oprimido?
        if (reset_btn && !rst_out_reg) begin
            counter <= 26'd0;
            latido <= 1'b0;
            medio_sg_reg <= 0;
            rst_out_reg <= 1'b1;
            samp_rate <= 0;
            counter8K <= 10'd750;
        end

        // Antirebote de botón reset, temporiza 100 uSg.
        if ( counter == 26'd1200 && rst_out_reg ) begin
            counter <= 26'd0;
            rst_out_reg <= 1'b0;
        end
	
	// seconds counter
        if ( counter == 26'd6000000 ) begin
            counter <= 26'd0;
            medio_sg_reg <= ~medio_sg_reg;      // Pasó 0.5 Sg Toggle
            latido <= (medio_sg_reg) ? 1'b1 : 1'b0;
        end
        latido <= ((medio_sg_reg == 1'b1) && (counter <= 26'd1200000)) ? 1'b1 : 1'b0;
        
        counter8K <= counter8K - 1;
        if (counter8K == 10'd0) begin
            counter8K <= 10'd750;
            samp_rate <= ~samp_rate;
        end
    end    

endmodule
