module fpu_class(input [63:0] f, output nan, output infinity, output zero, output subnormal, output normal);
    wire expOnes = &f[62:52];
    wire expZero = ~|f[62:52];
    wire fracZero = ~|f[51:0];
 
    assign nan = expOnes & ~fracZero;
    assign infinity = expOnes & fracZero;
    assign zero = expZero & fracZero;
    assign subnormal = expZero & ~fracZero;
    assign normal = ~expOnes & ~expZero;
endmodule

module fpu_mul(input [63:0] a, input [63:0] b, output reg [63:0] result);
    wire aNan, aInf, aZero, aSubnormal, aNormal;
    wire bNan, bInf, bZero, bSubnormal, bNormal;

    fpu_class classA(.f(a), .nan(aNan), .infinity(aInf), .zero(aZero), .subnormal(aSubnormal), .normal(aNormal));
    fpu_class classB(.f(b), .nan(bNan), .infinity(bInf), .zero(bZero), .subnormal(bSubnormal), .normal(bNormal));

    function [5:0] count_leading_zeros(input [52:0] sig);
        integer i;
        begin : clz_loop
            count_leading_zeros = 0;
            for (i = 52; i >= 0; i = i - 1) begin
                if (sig[i]) disable clz_loop;
                else count_leading_zeros = count_leading_zeros + 1;
            end
        end
    endfunction

    reg signed [12:0] shiftAmount;
    reg guard, round_bit, sticky;
    reg [52:0] sigFinal;
    reg [52:0] sigA;
    reg [52:0] sigB;

    reg [5:0] shift;
    reg signed [12:0] expA, expB;
    reg signed [12:0] expResult;
    reg [105:0] sigResult;
    reg sign;

    always @(*) begin
        if (aNan | bNan) begin
            result = 64'h7ff8000000000000; // propagated NaN
        end else if ((aInf & bZero) | (bInf & aZero)) begin
            result = 64'h7ff8000000000000; // generated NaN (inf*0)
        end else if ((aInf & ~bZero) | (~aZero & bInf)) begin
            result = {a[63] ^ b[63], 11'h7ff, 52'h0};
        end else if (aZero | bZero) begin
            result = {a[63] ^ b[63], 63'h0}; // Zero
        end else begin
            // For normal and subnormal numbers, we would need to implement the actual multiplication logic, which is complex and involves handling the exponent and significand separately. This is a placeholder for the actual multiplication logic.
            result = 64'h0; // Placeholder
            result[63] = a[63] ^ b[63]; // Sign bit

            sigA = {aNormal, a[51:0]};
            sigB = {bNormal, b[51:0]};

            // pre-normalize subnormal numbers
            if (aNormal) begin
                expA = a[62:52] - 1023; // Unbias the exponent
            end else begin
                shift = count_leading_zeros(sigA);
                sigA = sigA << shift; // Normalize the significand
                expA = -1022 - shift; // Adjust exponent for subnormal
            end
            if (bNormal) begin
                expB = b[62:52] - 1023; // Unbias the exponent
            end else begin
                shift = count_leading_zeros(sigB);
                sigB = sigB << shift; // Normalize the significand
                expB = -1022 - shift; // Adjust exponent for subnormal
            end

            expResult = expA + expB + 1023; // Add exponents
            sigResult = sigA * sigB; // Multiply significands

            if (sigResult[105]) begin
                expResult = expResult + 1; // Normalize if the result is too large
                sigResult = sigResult >> 1;
            end

            // Rounding
            // [104] is the leading bit
            // [103: 52] are the fraction bits
            // [51] guard bit, [50] round bit, and [49:0] sticky bits
            sigFinal = sigResult[104:52];

            guard = sigResult[51];
            round_bit = sigResult[50];
            sticky = |sigResult[49:0];
            // 000 to 011 would round down, 101 to 111 would round up, and 100 would round to the nearest even
            if (guard & (round_bit | sigFinal[0] | sticky)) begin
                sigFinal = sigFinal + 1; // Round up
                if (sigFinal == 53'h20000000000000) begin
                    expResult = expResult + 1; // Handle rounding overflow
                    sigFinal = 53'h10000000000000; // Reset to normalized value
                end
            end

            // Handle overflow and underflow
            sign = a[63] ^ b[63];
            if (expResult >= 2047) begin
                result = {sign, 11'h7ff, 52'h0}; // Overflow to Infinity
            end else if (expResult <= 0) begin
                shiftAmount = 1 - expResult; // Calculate how much to shift for subnormal
                if (shiftAmount < 53) begin
                    sigFinal = sigFinal >> shiftAmount; // Shift to create subnormal result
                    result = {sign, 11'h0, sigFinal[51:0]}; // Subnormal result
                end else begin
                    result = {sign, 63'h0}; // Underflow to Zero
                end
            end else begin
                result = {sign, expResult[10:0], sigFinal[51:0]}; // Normalized result
            end
        end
    end
endmodule

module fpu_add(input [63:0] a, input [63:0] b, output reg [63:0] result);
    // Similar to multiplication, we would need to implement the actual addition logic, which involves aligning the exponents and adding the significands. This is a placeholder for the actual addition logic.
    wire aNan, aInf, aZero, aSubnormal, aNormal;
    wire bNan, bInf, bZero, bSubnormal, bNormal;

    fpu_class classA(.f(a), .nan(aNan), .infinity(aInf), .zero(aZero), .subnormal(aSubnormal), .normal(aNormal));
    fpu_class classB(.f(b), .nan(bNan), .infinity(bInf), .zero(bZero), .subnormal(bSubnormal), .normal(bNormal));

    function [5:0] count_leading_zeros(input [55:0] sig);
        integer i;
        begin : clz_loop
            count_leading_zeros = 0;
            for (i = 55; i >= 0; i = i - 1) begin
                if (sig[i]) disable clz_loop;
                else count_leading_zeros = count_leading_zeros + 1;
            end
        end
    endfunction

    reg [52:0] augendSig;
    reg [52:0] addendSig;
    reg signed [12:0] shift;
    reg signed [12:0] expResult;
    reg signed [12:0] expA, expB;
    reg sign;

    reg guard, round_bit, sticky;
    reg [55:0] extAugend;
    reg [55:0] extAddend;
    reg [52:0] sigFinal;

    reg [56:0] sumSig;
    reg [56:0] diffSig;
    reg [12:0] shiftAmount;

    always @(*) begin
        if (aNan | bNan) begin
            result = 64'h7ff8000000000000; // propagated NaN
        end else if ((aInf | bInf)) begin
            if ((aInf & bInf) & (a[63] ^ b[63])) begin
                result = 64'hfff8000000000000; // generated NaN (inf - inf)
            end else begin
                if (aInf & ~bInf) begin
                    result = a;
                end else if (~aInf & bInf) begin
                    result = b;
                end else begin
                    result = a; // both same-sign infinity, return either
                end
            end
        end else if (aZero & bZero) begin
            result = {(a[63] & b[63]), 63'h0}; // Zero, negative zero if both is negative
        end else if (aZero) begin
            result = b;
        end else if (bZero) begin
            result = a;
        end else begin
            expA = aNormal ? a[62:52] : 11'd1; 
            expB = bNormal ? b[62:52] : 11'd1;

            if (expA > expB) begin
                augendSig[52:0] = {aNormal, a[51:0]};
                addendSig[52:0] = {bNormal, b[51:0]};
                sign = a[63];
                expResult = expA;
                shift = expA - expB;
            end else if (expA < expB) begin
                augendSig[52:0] = {bNormal, b[51:0]};
                addendSig[52:0] = {aNormal, a[51:0]};
                sign = b[63];
                expResult = expB;
                shift = expB - expA;
            end else begin
                shift = 0;
                expResult = expA;
                if (a[63] == b[63]) begin
                    sign = a[63];
                    augendSig[52:0] = {aNormal, a[51:0]};
                    addendSig[52:0] = {bNormal, b[51:0]};
                end else begin
                    if (a[51:0] > b[51:0]) begin
                        sign = a[63];
                        augendSig[52:0] = {aNormal, a[51:0]};
                        addendSig[52:0] = {bNormal, b[51:0]};
                    end else if (a[51:0] < b[51:0]) begin
                        sign = b[63];
                        augendSig[52:0] = {bNormal, b[51:0]};
                        addendSig[52:0] = {aNormal, a[51:0]};
                    end else begin
                        sign = 0;
                        augendSig[52:0] = {bNormal, b[51:0]};
                        addendSig[52:0] = {aNormal, a[51:0]};
                    end
                end
            end
            
            extAugend = {augendSig, 3'b0}; // Extend augend significand for potential overflow
            extAddend = {addendSig, 3'b0}; // Extend addend significand for potential overflow
            sticky = shift == 0 ? 0 : |(extAddend << (56 - shift));

            extAddend = extAddend >> shift; // Align addend significand to augend

            if (a[63] == b[63]) begin // addition
                sumSig = extAugend + extAddend; // Add significands

                // Normalize the result
                if (sumSig[56]) begin
                    expResult = expResult + 1; // Normalize if the result is too large
                    sticky = sticky | sumSig[0]; // Update sticky bit with the bit that will be shifted out
                    sumSig = sumSig >> 1;
                end

                // Rounding
                guard = sumSig[2];
                round_bit = sumSig[1];
                sticky = sticky | sumSig[0]; // Update sticky bit with the bit that will be shifted out


                sigFinal = sumSig[55:3]; // The final significand after shifting out the guard, round, and sticky bits
                if (guard & (round_bit | sumSig[3] | sticky)) begin
                    sigFinal = sigFinal + 1;
                    if (sigFinal == 53'h20000000000000) begin
                        expResult = expResult + 1; // Handle rounding overflow
                        sigFinal = 53'h10000000000000; // Reset to normalized value
                    end
                end

                if (expResult >= 2047) begin
                    result = {sign, 11'h7ff, 52'h0}; // Overflow to Infinity
                end else if (expResult < -1074) begin
                    result = {sign, 63'h0}; // Underflow to Zero
                end else if (expResult <= 0) begin
                        shiftAmount = 1 - expResult; // Calculate how much to shift for subnormal
                        if (shiftAmount < 53) begin
                            sigFinal = sigFinal >> shiftAmount; // Shift to create subnormal result
                            result = {sign, 11'h0, sigFinal[51:0]}; // Subnormal result
                        end else begin
                            result = {sign, 63'h0}; // Underflow to Zero
                        end
                end else begin
                    result = {sign, expResult[10:0], sigFinal[51:0]};
                end
            end else begin // subtraction
                diffSig = extAugend - extAddend; // Subtract significands

                if (diffSig == 0) begin
                    result = {sign, 63'h0}; // Result is zero
                end else begin
                    shiftAmount = count_leading_zeros(diffSig[55:0]);
                    
                    if (shiftAmount < expResult) begin
                        expResult = expResult - shiftAmount; // Adjust exponent for normalization
                        diffSig = diffSig << shiftAmount; // Normalize the significand
                    end else begin
                        diffSig = diffSig << (expResult - 1); // Shift to create subnormal result
                        expResult = 0; // Handle the case where the leading bit is just below the guard bit
                    end
                    // Rounding
                    guard = diffSig[2];
                    round_bit = diffSig[1];
                    sticky = sticky | diffSig[0]; // Update sticky bit with the bit that will be shifted out
                    
                    sigFinal = diffSig[55:3]; // The final significand after shifting out the guard, round, and sticky bits
                    if (guard & (round_bit | diffSig[3] | sticky)) begin
                        sigFinal = sigFinal + 1;
                        if (sigFinal == 53'h20000000000000) begin
                            expResult = expResult + 1; // Handle rounding overflow
                            sigFinal = 53'h10000000000000; // Reset to normalized value
                        end
                    end

                    if (expResult < -1074) begin
                        result = {sign, 63'h0};
                    end else begin
                        result = {sign, expResult[10:0], sigFinal[51:0]};
                    end
                end
            end
        end
    end
endmodule

module fpu_div(input [63:0] a, input [63:0] b, output reg [63:0] result);
    wire aNan, aInf, aZero, aSubnormal, aNormal;
    wire bNan, bInf, bZero, bSubnormal, bNormal;

    fpu_class classA(.f(a), .nan(aNan), .infinity(aInf), .zero(aZero), .subnormal(aSubnormal), .normal(aNormal));
    fpu_class classB(.f(b), .nan(bNan), .infinity(bInf), .zero(bZero), .subnormal(bSubnormal), .normal(bNormal));

    function [5:0] count_leading_zeros(input [52:0] sig);
        integer i;
        begin : clz_loop
            count_leading_zeros = 0;
            for (i = 52; i >= 0; i = i - 1) begin
                if (sig[i]) disable clz_loop;
                else count_leading_zeros = count_leading_zeros + 1;
            end
        end
    endfunction

    reg [56:0] q;
    reg[109:0] dividend;
    reg[52:0] divisor;
    reg [109:0] r;
    reg guard, round_bit, sticky;
    reg [52:0] sigFinal;
    reg signed [12:0] shiftAmount;
    reg sign;

    reg signed [12:0] expResult;
    integer i;

    reg signed [12:0] expA, expB;
    reg [52:0] sigA, sigB;
    reg [5:0] shift;

    always @(*) begin

        sign = a[63] ^ b[63];
        if (aNan | bNan) begin
            result = 64'h7ff8000000000000; // propagated NaN
        end else if (aInf & bInf) begin
            result = 64'hfff8000000000000; // generated NaN (inf/inf)
        end else if (aInf) begin
            result = {sign, 11'h7ff, 52'h0}; // inf/anything = inf
        end else if (bZero) begin
            result = 64'h7ff8000000000000; // NaN (num/0, 0/0)
        end else if (aZero) begin
            result = {sign, 63'h0}; // Zero
        end else if (bInf) begin
            result = {sign, 63'h0}; // num/inf = Zero
        end else begin
            // For normal and subnormal numbers, we would need to implement the actual division logic, which is complex and involves handling the exponent and significand separately. This is a placeholder for the actual division logic.
            sigA = {aNormal, a[51:0]};
            sigB = {bNormal, b[51:0]};

            if (aNormal) begin
                expA = a[62:52] - 1023;
            end else begin
                shift = count_leading_zeros(sigA);
                sigA = sigA << shift;
                expA = -1022 - shift;
            end
            if (bNormal) begin
                expB = b[62:52] - 1023;
            end else begin
                shift = count_leading_zeros(sigB);
                sigB = sigB << shift;
                expB = -1022 - shift;
            end

            expResult = expA - expB + 1023;

            divisor = sigB;
            q = 0;
            r = {57'b0, sigA};

            // Initial quotient bit (integer part of sigA/sigB)
            if (r >= {57'b0, divisor}) begin
                r = r - {57'b0, divisor};
                q[0] = 1'b1;
            end

            // Generate 56 fractional quotient bits
            for (i = 0; i < 56; i = i + 1) begin
                r = r << 1;
                q = q << 1;
                if (r >= {57'b0, divisor}) begin
                    r = r - {57'b0, divisor};
                    q[0] = 1'b1;
                end
            end

            // Normalize so q[55] is the leading 1
            if (q[56]) begin
                sticky = q[0] | (r != 0);
                q = q >> 1;
            end else begin
                expResult = expResult - 1;
                sticky = (r != 0);
            end

            // Rounding (round to nearest even)
            guard = q[2];
            round_bit = q[1];
            sticky = sticky | q[0];

            sigFinal = q[55:3];
            if (guard & (round_bit | sigFinal[0] | sticky)) begin
                sigFinal = sigFinal + 1;
                if (sigFinal == 53'h20000000000000) begin
                    expResult = expResult + 1;
                    sigFinal = 53'h10000000000000;
                end
            end

            if (expResult >= 2047) begin
                result = {sign, 11'h7ff, 52'h0};
            end else if (expResult < -1074) begin
                result = {sign, 63'h0};
            end else if (expResult <= 0) begin
                shiftAmount = 1 - expResult; // Calculate how much to shift for subnormal
                if (shiftAmount < 53) begin
                    sigFinal = sigFinal >> shiftAmount; // Shift to create subnormal result
                    result = {sign, 11'h0, sigFinal[51:0]}; // Subnormal result
                end else begin
                    result = {sign, 63'h0}; // Underflow to Zero
                end
            end else begin
                result = {sign, expResult[10:0], sigFinal[51:0]};
            end
        end
    end
endmodule