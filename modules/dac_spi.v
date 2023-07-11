module dac_spi(
    input   clock_in,
    input   reset,
    
    input [15:0] dac_data,       // Dato a transmitir a la PC desde Mercurial
    input   dac_rq,              // Alto para indicar que hay un dato desde Mercurial a transmitir
    output  dac_st,              // Flanco positivo cuando el dato fue leído por este módulo
    
    output sdata,
    output bclk,
    output nsync                 // SYNC del AD5061

    );

    localparam PAM_CLKS_PER_BCLK = 4;
    localparam PAM_DATA_LENGHT = 24;
    
    // Estados para el DAC
    localparam ST_IDLE = 0;
    localparam ST_RUNNING = 1;
    localparam ST_BYTE_LOW = 2; 
    localparam ST_BYTE_HIGH = 3;
    
    localparam WIDTH_COUNT_BCLK = $clog2(PAM_CLKS_PER_BCLK);
    localparam WIDTH_COUNT_BITS = $clog2(PAM_DATA_LENGHT);

    /***************************************************************************
    * signals
    ****************************************************************************/

    reg dac_rq_reg;                             // Vale uno cuando recibe un pedido de conversión
    reg dac_st;                                 // Vale cero si el DAC está disponible para nueva conversión
    reg [1:0] estado_dac = ST_IDLE;             // Estado del DAC
    reg [23:0] sample_reg = 24'd0;              // Registro para enviar dato al DAC
    reg [WIDTH_COUNT_BCLK-1:0] counter_bclk;    // Contador de decimación para el clock del DAC
    reg [WIDTH_COUNT_BITS-1:0] counter_bits;    // Contador de bits enviados al DAC por muestra
    reg reset_reg;
    
    /***************************************************************************
     * assignments
     ****************************************************************************/
    assign sdata = sample_reg[23];

    always @ (posedge clock_in) begin
        dac_rq_reg <= dac_rq;
        reset_reg <= reset;
        if (reset_reg) begin
            estado_dac <= ST_IDLE;
            dac_st <= 1'b0;
            sample_reg <= 24'd0;
            counter_bits <= 0;
            nsync <= 1'b1;
        end
        else begin
            case (estado_dac)
                ST_IDLE:
                begin
                    sample_reg <= 24'd0;
                    nsync <= 1'b1;
                    counter_bits <= 0;
                    counter_bclk <= 0;
                    if (dac_rq_reg && !dac_st) begin
                        sample_reg[15:0] <= dac_data[15:0];
                        estado_dac <= ST_RUNNING;
                        dac_st <= 1'b1;
                    end
                end
                
                ST_RUNNING:
                begin
                    nsync <= 1'b0;
                    
                    if (counter_bclk == PAM_CLKS_PER_BCLK/2) begin
                        bclk <= 0;
                        counter_bclk <= counter_bclk + 1;
                    end else if (counter_bclk == PAM_CLKS_PER_BCLK-1) begin
                        bclk <= 1;
                        sample_reg <= sample_reg << 1;
                        counter_bits <= counter_bits + 1;
                        counter_bclk <= 0;
                    end else begin
                        counter_bclk <= counter_bclk + 1;
                    end
                                        
                    if ((counter_bits == PAM_DATA_LENGHT-1) && (counter_bclk == PAM_CLKS_PER_BCLK-1)) begin
                        // Llegó al final del envio de una muestra
                        dac_st <= 1'b0;
                        estado_dac <= ST_IDLE;
                    end
                end
                
                default:
                begin
                    estado_dac <= ST_IDLE;
                end
            endcase
        
        end
    end    

endmodule

    //// Control de DAC
    //always @ (posedge hwclk) begin
        //nsync <= nsync;
        //estado_dac <= estado_dac;
        //sample_reg <= sample_reg;
        //counter_bits <= counter_bits;
        //if (reset) begin
            //estado_dac <= ST_IDLE;
            //dac_idle <= 1'b1;
            //sample_reg <= 24'd0;
            //counter_bits <= 0;
            //nsync <= 1'b1;
        //end
        //else if (estado == 4'd10) begin
            //case (estado_dac)
                //ST_IDLE:
                //begin
                    //sample_reg <= 24'd0;
                    //nsync <= 1'b1;
                    //counter_bits <= 0;
                    //counter_bclk <= 0;
                    //if (muestra_lista) begin
                        //sample_reg[15:0] <= muestra[15:0];
                        //estado_dac <= ST_RUNNING;
                        //dac_idle <= 1'b0;
                    //end
                //end
                
                //ST_RUNNING:
                //begin
                    //nsync <= 1'b0;
                    
                    //if (counter_bclk == PAM_CLKS_PER_BCLK/2) begin
                        //bclk <= 0;
                        //counter_bclk <= counter_bclk + 1;
                    //end else if (counter_bclk == PAM_CLKS_PER_BCLK-1) begin
                        //bclk <= 1;
                        //sample_reg <= sample_reg << 1;
                        //counter_bits <= counter_bits + 1;
                        //counter_bclk <= 0;
                    //end else begin
                        //counter_bclk <= counter_bclk + 1;
                    //end
                                        
                    //if ((counter_bits == PAM_DATA_LENGHT-1) && (counter_bclk == PAM_CLKS_PER_BCLK-1)) begin
                        //// Llegó al final del envio de una muestra
                        //dac_idle <= 1'b1;
                        //estado_dac <= ST_IDLE;
                    //end
                //end
                
                //default:
                //begin
                    //estado_dac <= ST_IDLE;
                //end
            //endcase
        //end
        //else begin
            //estado_dac <= ST_IDLE;
            //sample_reg <= 24'd0;
            //nsync <= 1'b1;
        //end
    //end

