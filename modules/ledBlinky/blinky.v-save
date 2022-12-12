/* LED blinky */

module blinky( 
    // Inputs
    input piClk,
    input piRst,
    //input piEna,
    // Outputs
    output poLed );

    parameter c_bit_counter = 25;
    reg  [c_bit_counter:0] s_counter_reg;
    wire [c_bit_counter:0] s_counter_next;

    // Main counter Reg
    always @ (posedge piClk) begin
        if ( piRst == 1'b1 ) begin
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
    assign poLed = (s_counter_reg >= {{1'b0}, {(c_bit_counter-1){1'b1}}} ) ? 1'b1 : 1'b0;

endmodule
