
"""
    AbstractCircuitGate{N}

Abtract unitary quantum circuit gate. `N` is the overall number of quantum "wires" of the circuit.
"""
abstract type AbstractCircuitGate{N} end


"utility function for enumerating cartesian tuples"
cartesian_tuples(d::Integer, N::Integer) = Tuple.(CartesianIndices(Tuple(fill(0:d-1, N))))

struct CircuitGate{M,N,G} <: AbstractCircuitGate{N}
    "ordered wire indices which this gate acts on"
    iwire::NTuple{M, <:Integer}
    "actual gate"
    gate::G

    function CircuitGate{M,N,G}(iwire::NTuple{M, <:Integer}, gate::G) where {M,N,G}
        M ≥ 1 || error("Need at least one wire to act on.")
        M ≤ N || error("Number of gate wires cannot be larger than total number of wires.")
        length(unique(iwire)) == M || error("Wire indices must be unique.")
        minimum(iwire) ≥ 1 || error("Wire index cannot be smaller than 1.")
        maximum(iwire) ≤ N || error("Wire index cannot be larger than total number of wires.")
        G <: AbstractGate{M} || error("Gate type must be a subtype of AbstractGate{$M}.")
        new{M,N,G}(iwire, gate)
    end
end

function CircuitGate(iwire::NTuple{M, <:Integer}, gate::AbstractGate{M}, N) where {M}
    CircuitGate{M,N,typeof(gate)}(iwire, gate)
end

function Base.isapprox(cg1::CircuitGate{M, N, G}, cg2::CircuitGate{M, N, G}) where {M, N, G}
    fields = fieldnames(G)
    for name in fields
        if getfield(cg1.gate, name) ≈ getfield(cg2.gate, name)
        else
            return false
        end
    end
    return true
end

function matrix(cg::CircuitGate{M,N,G}) where {M,N,G<:AbstractGate}
    # convert to array
    iwire = collect(cg.iwire)
    # complementary wires
    iwcompl = setdiff(1:N, iwire)
    @assert length(iwire) + length(iwcompl) == N

    # TODO: support general "qudits"
    d = 2

    # TODO: handle sparse matrices efficiently
    gmat = matrix(cg.gate)
    @assert size(gmat) == (d^M, d^M)

    # Note: following the ordering convention of `kron` here, i.e.,
    # last qubit corresponds to fastest varying index
    strides = [d^(N-j) for j in 1:N]
    wstrides = strides[iwire]
    cstrides = strides[iwcompl]

    rowind = fill(0, d^(N+M))
    colind = fill(0, d^(N+M))
    values = fill(zero(eltype(gmat)), d^(N+M))
    count = 0
    for kw in (N-M > 0 ? reverse.(cartesian_tuples(d, N-M)) : [Int[]])
        koffset = dot(collect(kw), cstrides)
        for (i, iw) in enumerate(reverse.(cartesian_tuples(d, M)))
            for (j, jw) in enumerate(reverse.(cartesian_tuples(d, M)))
                # rearrange wire indices according to specification
                count += 1
                rowind[count] = koffset + dot(collect(iw), wstrides) + 1
                colind[count] = koffset + dot(collect(jw), wstrides) + 1
                values[count] = gmat[i, j]
            end
        end
    end
    @assert count == d^(N+M)

    return dropzeros!(sparse(rowind, colind, values, d^N, d^N))
end

function Base.adjoint(cg::CircuitGate{M,N,G}) where {M,N,G}
    adj_gate = Base.adjoint(cg.gate)
    CircuitGate{M,N,typeof(adj_gate)}(cg.iwire, adj_gate)
end


single_qubit_circuit_gate(iwire::Integer, gate::AbstractGate{1}, N::Integer) =
    CircuitGate((iwire,), gate, N)

two_qubit_circuit_gate(iwire1::Integer, iwire2::Integer, gate::AbstractGate{2}, N::Integer) =
    CircuitGate((iwire1, iwire2), gate, N)


# single control and target wire
controlled_circuit_gate(icntrl::Integer, itarget::Integer, U::AbstractGate{1}, N::Integer) =
    controlled_circuit_gate((icntrl,), (itarget,), U, N)

# single control wire
controlled_circuit_gate(icntrl::Integer, itarget::NTuple{M, <:Integer}, U::AbstractGate{M}, N::Integer) where {M} =
    controlled_circuit_gate((icntrl,), itarget, U, N)

# single target wire
controlled_circuit_gate(icntrl::NTuple{K, <:Integer}, itarget::Integer, U::AbstractGate{1}, N::Integer)  where {K} =
    controlled_circuit_gate(icntrl, (itarget,), U, N)

function controlled_circuit_gate(icntrl::NTuple{K, <:Integer}, itarget::NTuple{M, <:Integer}, U::AbstractGate{M}, N::Integer) where {K,M}
    # consistency checks
    K + M ≤ N || error("Number of control and target wires must be smaller than overall number of wires.")
    length(intersect(icntrl, itarget)) == 0 || error("Control and target wires must be disjoint.")

    CircuitGate((icntrl..., itarget...), ControlledGate{M,K+M}(U), N)
end

"""
    Moment{N}

Represents an intermediary state within a given circuit. `N` is the overall number of quantum "wires" of the circuit.
"""

abstract type AbstractMoment{N} end

mutable struct Moment{N} <: AbstractMoment{N}
    gates::AbstractVector{<:AbstractCircuitGate{N}}
    function Moment{N}(g::AbstractCircuitGate{N}) where {N}
        new([g])
    end

    function Moment{N}(g::AbstractVector{<:AbstractCircuitGate{N}}) where {N}
        wires = Integer[]
        for gate in g
            length(intersect(wires, gate.iwire)) == 0 || error("Only gates on different wires are allowed in a Moment")
            append!(wires, gate.iwire)
        end
        new(g)
    end
end

function Base.adjoint(m::Moment{N}) where {N}
    return Moment{N}(Base.adjoint.(reverse(m.gates)))
end

# make Moment iterable and indexable
function Base.getindex(m::Moment{N}, i::Integer) where {N}
    1 <= i <= length(m.gates) || throw(BoundsError(m, i))
    return m.gates[i]
end

function Base.iterate(m::Moment{N}, state=1) where {N}
    return state > length(m.gates) ? nothing : (m[state], state+1)
end

# implement methods required for iteration
function Base.firstindex(m::Moment{N}) where {N}
    return 1
end

function Base.lastindex(m::Moment{N}) where {N}
    return length(m.gates)
end

function Base.length(m::Moment{N}) where {N}
    return length(m.gates)
end

function Base.isapprox(m1::Moment{N}, m2::Moment{N}) where {N}
    length(m1) == length(m2) || return false
    for (g1, g2) in zip(m1, m2)
        if !(g1 ≈ g2)
            return false
        end
    end
    return true
end


"""
    rdm(N, iwire, ψ, χ)

Compute the reduced density matrix ``tr_B[|ψ⟩⟨χ|]``, where the trace runs over
the subsystem complementary to the qubits specified by `iwire`.
"""
function rdm(N::Integer, iwire::NTuple{M, <:Integer}, ψ::AbstractVector, χ::AbstractVector) where {M}
    M ≥ 1 || error("Need at least one wire to act on.")
    M ≤ N || error("Number of gate wires cannot be larger than total number of wires.")
    length(unique(iwire)) == M || error("Wire indices must be unique.")
    minimum(iwire) ≥ 1 || error("Wire index cannot be smaller than 1.")
    maximum(iwire) ≤ N || error("Wire index cannot be larger than total number of wires.")

    # convert to array
    iwire = collect(iwire)
    # complementary wires
    iwcompl = setdiff(1:N, iwire)
    @assert length(iwire) + length(iwcompl) == N

    # TODO: support general "qudits"
    d = 2

    ρ = zeros(eltype(ψ), d^M, d^M)

    # Note: following the ordering convention of `kron` here, i.e.,
    # last qubit corresponds to fastest varying index
    strides = [d^(N-j) for j in 1:N]
    wstrides = strides[iwire]
    cstrides = strides[iwcompl]

    # TODO: optimize memory access pattern
    for kw in (N-M > 0 ? reverse.(cartesian_tuples(d, N-M)) : [Int[]])
        koffset = dot(collect(kw), strides[iwcompl])
        for (i, iw) in enumerate(reverse.(cartesian_tuples(d, M)))
            for (j, jw) in enumerate(reverse.(cartesian_tuples(d, M)))
                rowind = koffset + dot(collect(iw), strides[iwire]) + 1
                colind = koffset + dot(collect(jw), strides[iwire]) + 1
                ρ[i, j] += ψ[rowind] * conj(χ[colind])
            end
        end
    end

    return ρ
end


"""
    CircuitGateChain{N}

Chain of quantum circuit gates.
"""
mutable struct CircuitGateChain{N}
    moments::AbstractVector{<:AbstractMoment{N}}
    # gates::AbstractVector{<:AbstractCircuitGate{N}}
    function CircuitGateChain{N}(gates::AbstractVector{<:AbstractCircuitGate{N}}) where {N}
        moments = map(Moment{N}, gates)
        new(moments)
    end

    function CircuitGateChain{N}(moments::AbstractVector{<:AbstractMoment{N}}) where {N}
        new(moments)
    end

    function CircuitGateChain(gates::AbstractVector{<:AbstractCircuitGate{N}}) where {N}
        moments = map(Moment{N}, gates)
        new{N}(moments)
    end

    function CircuitGateChain(moments::AbstractVector{<:AbstractMoment{N}}) where {N}
        new{N}(moments)
    end
end

# unitary matrix representation of a sequence of circuit gates
function matrix(cgc::CircuitGateChain{N}) where {N}
    gates = AbstractCircuitGate{N}[]
    for moment in cgc
        append!(gates, moment.gates)
    end
    prod(Tuple(matrix(g) for g in reverse(gates)))
end

function Base.adjoint(cgc::CircuitGateChain{N}) where {N}
    return CircuitGateChain{N}(Base.adjoint.(reverse(cgc.moments)))
end

# make CircuitGateChain iterable and indexable
function Base.getindex(cgc::CircuitGateChain{N}, i::Integer) where {N}
    1 <= i <= length(cgc.moments) || throw(BoundsError(cgc, i))
    return cgc.moments[i]
end

function Base.iterate(cgc::CircuitGateChain{N}, state=1) where {N}
    return state > length(cgc.moments) ? nothing : (cgc[state], state+1)
end

# implement methods required for iteration
function Base.firstindex(cgc::CircuitGateChain{N}) where {N}
    return 1
end

function Base.lastindex(cgc::CircuitGateChain{N}) where {N}
    return length(cgc.moments)
end

function Base.length(cgc::CircuitGateChain{N}) where {N}
    return length(cgc.moments)
end

function Base.:*(cgc1::CircuitGateChain{N}, cgc2::CircuitGateChain{N}) where {N}
    append!(cgc1.moments, cgc2.moments)
    return cgc1
end

function (cgc::CircuitGateChain{N})(g::CircuitGate{M,N,G}) where {M,N,G<:AbstractGate}
    append!(cgc.moments, Moment([g]))
end

"""
    comm(A, B)

Matrix commutator [A, B].
"""
comm(A::AbstractMatrix, B::AbstractMatrix) = A*B - B*A


"""
    MeasurementOps{N}

Pairwise commuting measurement operators (Hermitian matrices).
"""
struct MeasurementOps{N}
    mops::AbstractVector{<:AbstractMatrix}

    function MeasurementOps{N}(mop::AbstractMatrix) where {N}
        # TODO: support general "qudits"
        d = 2
        # consistency checks
        size(mop) == (d^N, d^N) || error("Measurement operator must be a 2^N × 2^N matrix.")
        mop ≈ Base.adjoint(mop) || error("Measurement operator must be Hermitian.")
        new([mop])
    end

    function MeasurementOps{N}(mops::AbstractVector{<:AbstractMatrix}) where {N}
        # TODO: support general "qudits"
        d = 2
        # consistency checks
        for m in mops
            size(m) == (d^N, d^N) || error("Measurement operator must be a 2^N × 2^N matrix.")
            m ≈ Base.adjoint(m) || error("Measurement operator must be Hermitian.")
            for n in mops
                norm(comm(m, n))/d^N < 1e-13 || error("Measurement operators must pairwise commute.")
            end
        end
        new(mops)
    end
end


"""
    Circuit{N}

Quantum circuit consisting of a unitary gate chain and measurement operators.
"""
struct Circuit{N}
    cgc::CircuitGateChain{N}
    meas::MeasurementOps{N}
end

# make CircuitGateChain iterable and indexable
function Base.getindex(c::Circuit{N}, i::Integer) where {N}
    1 <= i <= length(c.cgc.moments) || throw(BoundsError(c, i))
    return c.cgc.moments[i]
end

function Base.iterate(c::Circuit{N}, state=1) where {N}
    return state > length(c.cgc.moments) ? nothing : (c.cgc[state], state+1)
end

# implement methods required for iteration
function Base.firstindex(c::Circuit{N}) where {N}
    return 1
end

function Base.lastindex(c::Circuit{N}) where {N}
    return length(c.cgc.moments)
end

function distribution(c::Circuit{N}, ψ::AbstractVector) where {N}
    return apply(c.cgc, ψ)
end
