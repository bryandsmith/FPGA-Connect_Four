# FPGA-Connect_Four
 A fully functional two-player Connect Four game written in System Verilog intended to run on the Terasic DE1-SoC FPGA development board

The Connect Four system consists of four primary modules working together to create a 
seamless gaming experience:  
1. DE1_SoC (Top-Level) - Integrates all components, handles I/O interfacing, and 
manages clock generation  
2. connect_four_controller - Implements the game FSM and generates control 
signals  
3. connect_four_datapath - Maintains board state, validates moves, and detects 
wins  
4. connect_four_display - Renders the game board onto the 16×16 LED matrix 
 
## Input/Output 
KEY0: Drop token in current column

KEY2: Move cursor right

KEY3: Move cursor left 

## Function 

SW9: System Reset

HEX0: Current player display (1 or 2)

HEX5-HEX1: Winner marquee animation

GPIO_1: 16 x 16 LED matrix control 
