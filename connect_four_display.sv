// -----------------------------------------------------------------------------
// Connect Four — Display
// -----------------------------------------------------------------------------
// Responsibilities:
// - Render the Connect Four board state onto a 16×16 LED matrix.
// - Draw static borders around the playfield.
// - Highlight the active cursor column in the top border (blinking).
// - Show winner/draw state by changing cursor highlight to solid orange.
// - Map board contents (Player 1 = red, Player 2 = green) into LED pixels.
// -----------------------------------------------------------------------------
module connect_four_display (
    // -------------------------------------------------------------------------
    // Inputs
    // -------------------------------------------------------------------------
    input  logic update_display,        // refresh LED array (not used internally, but kept for interface consistency)
    input  logic winner_enable,         // asserted when game has a winner
    input  logic game_over_enable,      // asserted when game ends in a draw
    input  logic [1:0] board[6][8],     // board state from datapath
    input  logic [1:0] current_player,  // active player (for cursor blink color)
    input  logic [2:0] cursor_col,      // active cursor column
    input  logic blink,                 // blink signal (~1–2 Hz)

    // -------------------------------------------------------------------------
    // Outputs
    // -------------------------------------------------------------------------
    output logic [15:0][15:0] RedPixels, // LED matrix red channel
    output logic [15:0][15:0] GrnPixels  // LED matrix green channel
);

    // =========================================================================
    // LED Matrix Layout Parameters
    // =========================================================================
    localparam int row_offset = 4; // vertical centering offset
    localparam int col_offset = 3; // horizontal centering offset

    // =========================================================================
    // LED Array Mapping Logic
    // =========================================================================
    always_comb begin
        // Clear entire matrix each cycle
        RedPixels = '0;
        GrnPixels = '0;

        // ---------------------------------------------------------------------
        // Draw left/right borders (vertical lines)
        // ---------------------------------------------------------------------
        for (int r=0; r<8; r++) begin
            RedPixels[row_offset+r][col_offset+0] = 1;
            GrnPixels[row_offset+r][col_offset+0] = 1;
            RedPixels[row_offset+r][col_offset+9] = 1;
            GrnPixels[row_offset+r][col_offset+9] = 1;
        end

        // ---------------------------------------------------------------------
        // Draw top and bottom borders (horizontal lines)
        // ---------------------------------------------------------------------
        for (int c=0; c<10; c++) begin
            // Top border row
            if (c>0 && c<9 && (c-1) == cursor_col) begin
                // Cursor highlight column
                if (winner_enable || game_over_enable) begin
                    // Game ended: solid orange (red+green together)
                    RedPixels[row_offset+0][col_offset+c] = 1;
                    GrnPixels[row_offset+0][col_offset+c] = 1;
                end else begin
                    // Game running: blink current player's color
                    case (current_player)
                        2'b01: RedPixels[row_offset+0][col_offset+c] = blink; // Player 1 cursor (red blink)
                        2'b10: GrnPixels[row_offset+0][col_offset+c] = blink; // Player 2 cursor (green blink)
                        default: begin
                            // Fallback: solid orange
                            RedPixels[row_offset+0][col_offset+c] = 1;
                            GrnPixels[row_offset+0][col_offset+c] = 1;
                        end
                    endcase
                end
            end else begin
                // Non-cursor top border cells: solid orange
                RedPixels[row_offset+0][col_offset+c] = 1;
                GrnPixels[row_offset+0][col_offset+c] = 1;
            end

            // Bottom border row (always solid orange)
            RedPixels[row_offset+7][col_offset+c] = 1;
            GrnPixels[row_offset+7][col_offset+c] = 1;
        end

        // ---------------------------------------------------------------------
        // Draw board contents (6×8 grid inside borders)
        // ---------------------------------------------------------------------
        for (int row=0; row<6; row++) begin
            for (int col=0; col<8; col++) begin
                case (board[row][col])
                    2'b01: RedPixels[row_offset+row+1][col_offset+col+1] = 1; // Player 1 piece
                    2'b10: GrnPixels[row_offset+row+1][col_offset+col+1] = 1; // Player 2 piece
                    default: ; // empty cell
                endcase
            end
        end
    end

endmodule