`include "../inc/module_params.v"

module top_level (
    input   hwclk,
    input   rst,
    output  [7:0] leds,
    output  pwm,
    output read,
    output fifo_empty,
    output fifo_full,

    // FT245 interface
    inout   [7:0] in_out_245,
    input   rxf_245,
    output  rx_245,
    input   txe_245,
    output  wr_245,

    // --- test ---
    output  tc_pwm_step,
    output  tc_pwm_symb,
    output  fake_rst,
    output  test_baudrate
);
    /***************************************************************************
     * test
     ***************************************************************************
     */
    assign fake_rst = 1'b1;

    /***************************************************************************
     * signals
     ***************************************************************************
     */
    reg clk;
    reg [7:0] led_reg;

    // FT245 - Simple Interface
    wire rx_valid_si, rx_ready_si;
    wire tx_valid_si, tx_ready_si;
    wire [7:0] rx_data_si, tx_data_si;

    // Inteface between fifo and modulator
    wire [7:0] sample;
    wire read_sample;

    // Inteface between control_unit and deco_unit
    wire tx, rx;
    wire [7:0] data_tx, data_rx;

    // Inteface between deco_unit and modulator
    wire new_sample;

    // test
    reg [26:0] count;

    assign read = read_sample;

    /***************************************************************************
     * assignments
     ***************************************************************************
     */
    assign leds = led_reg;


    /***************************************************************************
     * module instances
     ***************************************************************************
     */
    /* pll */
    pll_128MHz system_clk(
        .clock_in   (hwclk),
        .clock_out  (clk),
        .locked     (aux)
    );

    /* FT245 wrapper
     * Interface between FT245 FIFO and SIMPLE INTERFACE
     */
    ft245_block ft245_wrapper (
        .clk        (clk),
        .rst        (rst),
        // FT245 interface
        .in_out_245 (in_out_245),
        .rxf_245    (rxf_245),
        .rx_245     (rx_245),
        .txe_245    (txe_245),
        .wr_245     (wr_245),
        // simple interface - RX
        .rx_data_si (rx_data_si),
        .rx_valid_si(rx_valid_si),
        .rx_ready_si(!fifo_full),
        // simple interface - TX
        .tx_data_si (),
        .tx_valid_si(),
        .tx_ready_si()
    );

    fifo #(
        .DEPTH_WIDTH    (10),
        .DATA_WIDTH     (8)
    ) data_fifo (
        .clk        (clk),
        .rst        (rst),
        /* write port */
        .wr_data_i  (rx_data_si),
        .wr_en_i    (rx_valid_si & !fifo_full),
        /* read port */
        .rd_data_o  (sample),
        .rd_en_i    (read_sample),
        /* control signal */
        .full_o     (fifo_full),
        .empty_o    (fifo_empty)
        );

    modulator #(
        .FOO                    ('d10),
        .AM_CLKS_PER_PWM_STEP   (`AM_CLKS_PER_PWM_STEP), //'d1),
        .AM_PWM_STEP_PER_SAMPLE (`AM_PWM_STEP_PER_SAMPLE), //'d63),
        .AM_BITS_PER_SAMPLE     (`AM_BITS_PER_SAMPLE) //'d8)
    ) am_modulator (
        .clk    (clk),
        .rst    (rst),
        .enable (1'b1),
        /* FIFO interface */
        .sample (sample),
        .empty  (fifo_empty),
        .read   (read_sample),
        /* data flow */
        .pwm    (pwm),

        .tc_pwm_step(tc_pwm_step),
        .tc_pwm_symb(tc_pwm_symb)
    );

    /* Led keep alive */
    always @(posedge clk) begin
        if (rst == 1'b1) begin
            led_reg = 8'hFF;
            count = 27'd0;
        end else if (count == 27'd126000000) begin
            led_reg = led_reg + 1;
            count = 27'd0;
        end else begin
            count = count + 1;
        end
    end

endmodule

