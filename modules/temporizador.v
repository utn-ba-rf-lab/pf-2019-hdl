module temporizador(
    input  clock_in,
    input  reset_btn,
    output medio_sg,		// Toggle cada medio segundo
    output rst_out,		// Vale 1 si hubo reset por 100 uSg desde que suelto el botón
    output [7:0] samp_rates,    // 48, 44.1, 32, 24, 22.05, 16, 11.025, 8 KHz
    output latido		// Prende por 100 mSg cada segundo
    );
    
    localparam CLKS_48K = 124;          // ciclos de reloj por semiperiodo de 48 KHz

    reg [25:0] counter = 26'b0;         // Counter register - hwclk: 12MHz -> max counter 12e6
    reg [6:0] counter48K = CLKS_48K;    // Counter register 48 KSpS
    reg counter24K = 1'b1;              // Counter register 24 KSpS
    reg [1:0] counter16K = 2'd2;        // Counter register 16 KSpS
    reg [2:0] counter8K = 3'd5;         // Counter register 8 KSpS
    reg [7:0] counter32K = 8'd186;      // Counter register 32 KSpS
    reg [7:0] counter44K = 8'd135;      // Counter register 44.1 KSpS
    reg counter22K = 1'b1;              // Counter register 22.05 KSpS
    reg [1:0] counter11K = 2'd3;        // Counter register 11.025 KSpS
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
            samp_rates <= 8'b0;
            counter48K <= CLKS_48K;
            counter24K <= 1'b1;
            counter16K <= 2'd2;
            counter8K <= 3'd5;
            counter32K <= 8'd186;
            counter44K <= 8'd135;
            counter22K <= 1'b1;
            counter11K <= 2'd3;
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
        latido <= ((medio_sg_reg == 1'b1) && (counter <= 26'd600000)) ? 1'b1 : 1'b0;
        
        // 48 KHz
        if (counter48K == 7'd0 && !rst_out_reg) begin
            counter48K <= CLKS_48K;
            samp_rates[7] <= ~samp_rates[7];
            
            // 24 KHz
            if (counter24K == 1'b0) begin
                counter24K <= 1'b1;
                samp_rates[4] <= ~samp_rates[4];
            end
            else begin
                counter24K <= 1'b0;
            end
            
            // 16 KHz
            if (counter16K == 2'd0) begin
                counter16K <= 2'd2;
                samp_rates[2] <= ~samp_rates[2];
            end
            else begin
                counter16K <= counter16K - 1;
            end

            // 8 KHz
            if (counter8K == 3'd0) begin
                counter8K <= 3'd5;
                samp_rates[0] <= ~samp_rates[0];
            end
            else begin
                counter8K <= counter8K -1;
            end
        end
        else begin
            counter48K <= counter48K - 1;
        end
        
        // 32 KHz
        if (counter32K == 8'd0 && !rst_out_reg) begin
            counter32K <= samp_rates[5] ? 8'd187: 8'd186;
            samp_rates[5] <= ~samp_rates[5];
        end
        else begin
            counter32K <= counter32K - 1;
        end
                
        // 44.1 KHz
        if (counter44K == 8'd0 && !rst_out_reg) begin
            counter44K <= 8'd135;     // 44.1178 Khz, 0.0403 % de error (acelera)
            samp_rates[6] <= ~samp_rates[6];

            // 22.05 KHz (22.0589 KHz, 0,0403 % de error en exceso)
            if (counter22K == 3'd0) begin
                counter22K <= 1'b1;
                samp_rates[3] <= ~samp_rates[3];
            end
            else begin
                counter22K <= 1'b0;
            end

            // 11.025 KHz (11.0294 KHz, 0,0399 % de error en exceso)
            if (counter11K == 2'd0) begin
                counter11K <= 2'd3;
                samp_rates[1] <= ~samp_rates[1];
            end
            else begin
                counter11K <= counter11K -1;
            end

        end
        else begin
            counter44K <= counter44K - 1;
        end
                
    end    

endmodule
