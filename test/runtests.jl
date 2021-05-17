using FastBroadcast
using SparseArrays
using PerformanceTestTools, Test

const GROUP = get(ENV, "GROUP", "All")

function activate_downstream_env()
    Pkg.activate("downstream")
    Pkg.develop(PackageSpec(path=dirname(@__DIR__)))
    Pkg.instantiate()
end

if GROUP == "All" || GROUP == "Core"
    @testset "FastBroadcast" begin
        x, y = [1,2,3,4], [5,6,7,8]
        dst = zeros(Int, 4)
        bc = Broadcast.Broadcasted(+, (Broadcast.Broadcasted(*, (x, y)), x, y, x, y, x, y))
        bcref = copy(bc)
        @test FastBroadcast.fast_materialize!(dst, bc) == bcref
        dest = similar(bcref);
        @test (@.. dest = (x*y) + x + y + x + y + x + y) == bcref
        @test (@.. (x*y) + x + y + x + y + x + y) == bcref
        @test (@.. dest .+= (x*y) + x + y + x + y + x + y) ≈ 2bcref
        @test (@.. dest .-= (x*y) + x + y + x + y + x + y) ≈ bcref
        @test (@.. dest *= (x*y) + x + y + x + y + x + y) ≈ abs2.(bcref)
        nt = (x = x,)
        @test (@.. (nt.x*y) + x + y + x*(3,4,5,6) + y + x * (1,) + y + 3) ≈ (@. (x*y) + x + y + x*(3,4,5,6) + y + nt.x * (1,) + y + 3)
        A = rand(4,4);
        @test (@.. A * y' + x) ≈ (@. A * y' + x)
        @test (@.. A * transpose(y) + x) ≈ (@. A * transpose(y) + x)
        Ashim = A[1:1,:];
        @test (@.. Ashim * y' + x) ≈ (@. Ashim * y' + x) # test fallback
        Av = view(A,1,:);
        @test (@.. Av * y' + A) ≈ (@. Av * y' + A)
        B = similar(A);
        @.. B .= A
        @test B == A
        @.. A = 3
        @test all(==(3), A)
        @test (@.. 2 + 3 * 7 - cos(π)) === 24.0
        foo(f,x) = f(x)
        @test (@.. foo(abs2,x)) == abs2.(x)
      
        a = [1, 2]
        b = [3, 5]
        c = 1
        res = @.. @views a = c * b[1:2]
        @test res == (@. @views a = c * b[1:2])
        @test a === (@.. a)
        @static if VERSION >= v"1.6"
            var".foo"(a) = a
            @views @.. a = var".foo".(b[1:2]) .+ $abs2(c)
            @views @.. a = var".foo".(b[1:2]) .+ $(abs2(c))
            @test a == [4, 6]
        end

        @test (@.. x[2:3,1] + a) == [6, 9]
        r = copy(y);
        @test (@.. r[3:4] += x[2:3,1] + a) == [13,17]
        @test (@views @.. r[3:4] += x[2:3,1] + a) == [19,26]
        @test (@.. @views r[3:4] += x[2:3,1] + a) == [25,35]
        @test r == [5,6,25,35]
        @testset "Sparse" begin
            x = sparse([1, 2, 0, 4])
            y = sparse([1, 0, 0, 4])
            res = @.. x + y
            @test res isa SparseVector
            @test res == (@. x + y)
            res = @.. y = x + y
            @test res isa SparseVector
            @test res == [2, 2, 0, 8]
            res = @.. x = x + y
            @test res isa SparseVector
            @test res == [3, 4, 0, 12]
        end
    end

    VERSION >= v"1.6" && PerformanceTestTools.@include("vectorization_tests.jl")
end

if GROUP == "Downstream"
    activate_downstream_env()
end
