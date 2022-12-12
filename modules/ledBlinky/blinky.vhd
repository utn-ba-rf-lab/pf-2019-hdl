library ieee;
use ieee.std_logic_1164.all;

entity blinky is
    generic (   
        MAIN_COUNTER : natural := 1024;
    );
    port(   -- Inputs
            piClk   : in std_logic;
            piRst   : in std_logic;
            piEna   : in std_logic;
            -- Outputs
            poLed   : out std_logic;
    );
end blinky;

architecture arch of blinky is

    constant c_bit_counter  : natural := integer(ceil(log2(real(MAIN_COUNTER))));
    signal   s_counter_reg  : unsigned (c_bit_counter-1 downto 0);
    signal   s_counter_next : unsigned (c_bit_counter-1 downto 0);

begin

    -- Main counter Reg
    clkReg : process( piClk )
    begin
        if rising_edge( piClk ) then
            if ( piRst = '1' ) then
                s_counter_reg <= ( others => '0');
            elsif ( piEna = '1' ) then
                s_counter_reg <= s_counter_next;
            end if;
        end if;
    end process; 

    -- Adder for main counter
    s_counter_reg <= s_counter_next + 1;
    
    -- Output control
    poLed <= '1' when s_counter_reg >= (1, others => '0') else
             '0';
 end arch; -- arch