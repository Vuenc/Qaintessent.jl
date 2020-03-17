
"""
    qft_circuit(N)

Construct the quantum Fourier transform circuit for `N` qubits.
"""
function qft_circuit(N)
    mainblock = vcat([
            [j == i ?
             single_qubit_circuit_gate(i, HadamardGate(), N) :
             controlled_circuit_gate(j, i, PhaseShiftGate(2π/2^(j-i+1)), N) for j in i:N]
        for i in 1:N]...)
    swapblock = [two_qubit_circuit_gate(i, N-i+1, SwapGate(), N) for i in 1:(N÷2)]
    CircuitBlock(N > 1 ? [mainblock; swapblock] : mainblock)
end
