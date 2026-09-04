// DVI/HDMI TMDS 8b/10b エンコーダ (DVI 1.0 仕様どおり)
`default_nettype none
module tmds_encoder (
    input  wire       clk,
    input  wire       de,
    input  wire [1:0] ctrl,
    input  wire [7:0] d,
    output reg  [9:0] q
);
    wire [3:0] n1d = d[0]+d[1]+d[2]+d[3]+d[4]+d[5]+d[6]+d[7];
    wire       xnor_sel = (n1d > 4'd4) || (n1d == 4'd4 && d[0] == 1'b0);
    wire [8:0] qm;
    assign qm[0] = d[0];
    assign qm[1] = xnor_sel ? ~(qm[0] ^ d[1]) : (qm[0] ^ d[1]);
    assign qm[2] = xnor_sel ? ~(qm[1] ^ d[2]) : (qm[1] ^ d[2]);
    assign qm[3] = xnor_sel ? ~(qm[2] ^ d[3]) : (qm[2] ^ d[3]);
    assign qm[4] = xnor_sel ? ~(qm[3] ^ d[4]) : (qm[3] ^ d[4]);
    assign qm[5] = xnor_sel ? ~(qm[4] ^ d[5]) : (qm[4] ^ d[5]);
    assign qm[6] = xnor_sel ? ~(qm[5] ^ d[6]) : (qm[5] ^ d[6]);
    assign qm[7] = xnor_sel ? ~(qm[6] ^ d[7]) : (qm[6] ^ d[7]);
    assign qm[8] = ~xnor_sel;

    wire [3:0] n1q = qm[0]+qm[1]+qm[2]+qm[3]+qm[4]+qm[5]+qm[6]+qm[7];
    wire signed [4:0] diff = $signed({1'b0, n1q}) - 5'sd4;   // n1 - n0 = 2*n1 - 8 → /2
    reg  signed [4:0] cnt;

    always @(posedge clk) begin
        if (!de) begin
            cnt <= 5'sd0;
            case (ctrl)
                2'b00: q <= 10'b1101010100;
                2'b01: q <= 10'b0010101011;
                2'b10: q <= 10'b0101010100;
                default: q <= 10'b1010101011;
            endcase
        end else if (cnt == 0 || diff == 0) begin
            q   <= {~qm[8], qm[8], qm[8] ? qm[7:0] : ~qm[7:0]};
            cnt <= qm[8] ? cnt + diff : cnt - diff;
        end else if ((cnt > 0 && diff > 0) || (cnt < 0 && diff < 0)) begin
            q   <= {1'b1, qm[8], ~qm[7:0]};
            cnt <= cnt + $signed({4'b0, qm[8]}) - diff;
        end else begin
            q   <= {1'b0, qm[8], qm[7:0]};
            cnt <= cnt - $signed({4'b0, ~qm[8]}) + diff;
        end
    end
endmodule
`default_nettype wire
