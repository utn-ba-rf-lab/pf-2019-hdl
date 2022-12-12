/* LED blinky */

module blinky( 
    // Inputs
    input hwclk,
    input rst,
    //input piEna,
    // Outputs
    output [7:0]leds );

    parameter c_bit_counter = 25;
    reg  [c_bit_counter:0] s_counter_reg;
    wire [c_bit_counter:0] s_counter_next;

    // Main counter Reg
    always @ (posedge hwclk) begin
        if ( rst == 1'b1 ) begin
            s_counter_reg <= {c_bit_counter{1'b0}};
        end
        //else if ( piEna == 1'b1 ) begin
        else begin
            s_counter_reg <= s_counter_next;
        end
    end

    // Adder for main counter
    assign s_counter_next = s_counter_reg + 1;

    // Output logic
    assign leds[0] = (s_counter_reg >= {{1'b0}, {(c_bit_counter-1){1'b1}}} ) ? 1'b1 : 1'b0;

endmodule
