using TDAC
using LinearAlgebra, Test, HDF5, Random
using MPI
using FFTW
using StableRNGs

# Disable FFTW threads: they don't seem to help much in our case.  Also, they
# seem to cause deadlocks when running the tests, causing CI jobs to hang
# forever.
FFTW.set_num_threads(1)

@testset "LLW2d" begin
    using TDAC.LLW2d

    dx = dy = 2e3

    ### set_stations!
    ist = Vector{Int}(undef, 4)
    jst = Vector{Int}(undef, 4)
    LLW2d.set_stations!(ist, jst, 20e3, 20e3, 150e3, 150e3, dx, dy)
    @test ist == [75, 75, 85, 85]
    @test jst == [75, 85, 75, 85]
    ist = rand(Int, 9)
    jst = rand(Int, 9)
    LLW2d.set_stations!(ist, jst, 20e3, 20e3, 150e3, 150e3, dx, dy)

    @test ist == [75, 75, 75, 85, 85, 85, 95, 95, 95]
    @test jst == [75, 85, 95, 75, 85, 95, 75, 85, 95]

    ### initheight!
    eta = ones(2, 2)
    hh  = ones(2, 2)
    LLW2d.initheight!(eta, hh, dx, dy, 3e4)
    @test eta ≈ [0.978266982572228  0.9463188389826958;
                 0.9463188389826958 0.9154140546161575]
    eta = ones(2, 2)
    hh  = zeros(2, 2)
    LLW2d.initheight!(eta, hh, dx, dy, 3e4)
    @test eta ≈ zeros(2, 2)

    # timestep.  TODO: add real tests.  So far we're just making sure code won't
    # crash
    n = 200
    eta1 = rand(n, n)
    mm1 = rand(n, n)
    nn1 = rand(n, n)
    eta0 = rand(n, n)
    mm0 = rand(n, n)
    nn0 = rand(n, n)
    hn = rand(n, n)
    hm = rand(n, n)
    fm = rand(n, n)
    fn = rand(n, n)
    fe = rand(n,n)
    gg = rand(n,n)
    dxeta = Matrix{Float64}(undef, n, n)
    dyeta = Matrix{Float64}(undef, n, n)
    LLW2d.timestep!(dxeta, dyeta, eta1, mm1, nn1, eta0, mm0, nn0, hm, hn, fm, fn, fe, gg, dx, dy, 1)

    # setup.  TODO: add real tests.  So far we're just making sure code won't
    # crash
    LLW2d.setup(n, n, 3e4)
end

@testset "TDAC unit tests" begin
    dx = dy = 2e3

    @test TDAC.get_distance(3/2000, 4/2000, 0, 0, dx, dy) == 5
    @test TDAC.get_distance(10, 23, 5, 11, dx, dy) == 26000.0

    x = collect(reshape(1.0:9.0, 3, 3, 1))
    # stations at (1,1) (2,2) and (3,3) return diagonal of x[3,3]
    ist = [1,2,3]
    jst = [1,2,3]
    obs = Vector{Float64}(undef, 3)
    TDAC.get_obs!(obs,x,3,ist,jst)
    @test obs ≈ [1.,5.,9.]

    y = [1.0, 2.0]
    cov_obs = float(I(2))
    weights = Vector{Float64}(undef, 3)
    # model observations with equal distance from true observation return equal weights
    hx = [0.5 0.9 1.5; 2.1 2.5 1.9]
    TDAC.get_weights!(weights, y, hx, cov_obs)
    @test weights ≈ ones(3) / 3
    # model observations with decreasing distance from true observation return decreasing weights
    hx = [0.9 0.5 1.5; 2.1 2.5 3.5]
    TDAC.get_weights!(weights, y, hx, cov_obs)
    @test weights[1] > weights[2] > weights[3]

    # multivariate and independent methods give same weights when covariance matrix is diagonal
    weights2 = Vector{Float64}(undef, 3)
    TDAC.get_weights!(weights2, y, hx, 1.0)
    @test weights2 ≈ weights

    id = zeros(Int, 5)
    # equal weights return the same particles
    w = ones(5) * .2
    TDAC.resample!(id,w)
    @test sort(id) == [1,2,3,4,5]
    # weight of 1.0 on first particle returns only copies of that particle
    w = zeros(5)
    w[1] = 1.0
    TDAC.resample!(id,w)
    @test id == [1,1,1,1,1]
    # weight of 1.0 on last particle returns only copies of that particle
    w = zeros(5)
    w[end] = 1.0
    TDAC.resample!(id,w)
    @test id == [5,5,5,5,5]
    # weights of .4 and .6 on particles 2 and 4 return a 40/60 mix of those particles
    w = zeros(5)
    w[2] = .4
    w[4] = .6
    TDAC.resample!(id,w)
    @test sort(id) == [2,2,4,4,4]

    nx = 10
    ny = 10
    dt = 1.0
    nt = 1
    # 0 input gives 0 output
    x0 = x = zeros(nx, ny, 3)
    gg, hh, hm, hn, fm, fn, fe = TDAC.LLW2d.setup(nx,ny,3.0e4)
    @test size(gg) == size(hh) == size(hm) == size(fm) == size(fn) == size(fe) == (nx,ny)
    dxeta = Matrix{Float64}(undef, nx, ny)
    dyeta = Matrix{Float64}(undef, nx, ny)
    TDAC.tsunami_update!(dxeta, dyeta, x, nt, dx, dy, dt, hm, hn, fm, fn, fe, gg)
    @test x ≈ x0

    # Initialise and update a tsunami on a small grid
    s = 4e3
    eta = reshape(@view(x[1:nx*ny]), nx, ny)
    TDAC.LLW2d.initheight!(eta, hh, dx, dy, s)
    @test eta[2,2] ≈ 1.0
    @test sum(eta) ≈ 4.0
    TDAC.tsunami_update!(dxeta, dyeta, x, nt, dx, dy, dt, hm, hn, fm, fn, fe, gg)
    @test sum(eta, dims=1) ≈ [0.9140901416339269 1.7010577375770561 0.9140901416339269 0.06356127284539884 0.0 0.0 0.0 0.0 0.0 0.0]
    @test sum(eta, dims=2) ≈ [0.9068784611641829; 1.6999564781646717; 0.9204175965604575; 0.06554675780099671; 0.0; 0.0; 0.0; 0.0; 0.0; 0.0]

    # Test gaussian random field sampling
    x = 1.:2.
    y = 1.:2.
    grf = TDAC.init_gaussian_random_field_generator(1.0,1.0,1.0,x,y,0,false)
    f = zeros(2, 2)
    rnn = [9.,9.,9.,9.]
    TDAC.sample_gaussian_random_field!(f,grf,rnn)
    @test f ≈ [16.2387054353321 5.115956753643808; 5.115956753643809 2.8210669567042155]

    # Test IO
    params = TDAC.get_params(joinpath(@__DIR__, "io_unit_test.yaml"))
    rm(params.output_filename, force=true)
    data1 = collect(reshape(1.0:(params.nx * params.ny), params.nx, params.ny, 1))
    data2 = randn(params.nx, params.ny, 1)
    tstep = 0
    h5open(params.output_filename, "cw") do file
        TDAC.write_surface_height(file, data1, "m", tstep, params.title_syn, params)
        TDAC.write_surface_height(file, data2, "inch", tstep, params.title_avg, params)
    end
    @test h5read(params.output_filename, params.state_prefix * "_" * params.title_syn * "/t0/height") ≈ data1
    @test h5read(params.output_filename, params.state_prefix * "_" * params.title_avg * "/t0/height") ≈ data2
    attr = h5readattr(params.output_filename, params.state_prefix * "_" * params.title_syn * "/t0/height")
    @test attr["Unit"] == "m"
    @test attr["Time_step"] == tstep
    attr = h5readattr(params.output_filename, params.state_prefix * "_" * params.title_avg * "/t0/height")
    @test attr["Unit"] == "inch"
    @test attr["Time_step"] == tstep
    TDAC.write_params(params)
    attr = h5readattr(params.output_filename, params.title_params)
    @test attr["nx"] == params.nx
    @test attr["ny"] == params.ny
    @test attr["dx"] == params.dx
    @test attr["dy"] == params.dy
    @test attr["title_avg"] == params.title_avg
    @test attr["title_syn"] == params.title_syn
    @test attr["verbose"] == params.verbose
    TDAC.write_grid(params)
    attr = h5readattr(params.output_filename, params.title_grid * "/x")
    @test attr["Unit"] == "m"
    attr = h5readattr(params.output_filename, params.title_grid * "/y")
    @test attr["Unit"] == "m"

    stations = TDAC.StationVectors(zeros(Int,4), zeros(Int,4))
    TDAC.set_stations!(stations, params)
    @test stations.ist == [5, 5, 10, 10]
    @test stations.jst == [5, 10, 5, 10]
    TDAC.write_stations(stations, params)
    @test h5read(params.output_filename, params.title_stations * "/x") ≈ stations.ist .* params.dx
    @test h5read(params.output_filename, params.title_stations * "/y") ≈ stations.jst .* params.dy
    attr = h5readattr(params.output_filename, params.title_stations * "/x")
    @test attr["Unit"] == "m"
    attr = h5readattr(params.output_filename, params.title_stations * "/y")
    @test attr["Unit"] == "m"

    rm(params.output_filename, force=true)
end

@testset "TDAC integration tests" begin

    # Test true state with standard parameters
    x_true,x_avg,x_var = TDAC.tdac(joinpath(@__DIR__, "integration_test_1.yaml"))
    data_true = h5read(joinpath(@__DIR__, "reference_data.h5"), "integration_test_1")
    @test x_true ≈ data_true

    # Test true state with different parameters
    x_true,x_avg,x_var = TDAC.tdac(joinpath(@__DIR__, "integration_test_2.yaml"))
    data_true = h5read(joinpath(@__DIR__, "reference_data.h5"), "integration_test_2")
    @test x_true ≈ data_true

    # Test particle state with ~zero noise
    x_true,x_avg,x_var = TDAC.tdac(joinpath(@__DIR__, "integration_test_3.yaml"))
    @test x_true ≈ x_avg
    @test x_var .+ 1.0 ≈ ones(size(x_var))

    # Test particle state with noise
    rng = StableRNG(123)
    x_true,x_avg,x_var = TDAC.tdac(joinpath(@__DIR__, "integration_test_4.yaml"), rng)
    avg_ref = h5read(joinpath(@__DIR__, "reference_data.h5"), "integration_test_4")
    @test x_avg ≈ avg_ref

    # Test that different seed gives different result
    rng = StableRNG(124)
    x_true,x_avg,x_var = TDAC.tdac(joinpath(@__DIR__, "integration_test_4.yaml"), rng)
    @test !(x_avg ≈ avg_ref)

end

@testset "MPI" begin
    script = joinpath(@__DIR__, "mpi.jl")
    mktempdir() do dir
        cd(dir) do
            mpiexec() do cmd
                run(`$(cmd) -n 2 $(Base.julia_cmd()) $(script)`)
                # This is a dummy test.  If `run` exitsts successfully, this
                # testset will be successful as well, if `run` errors out this
                # testset will error out as well, and the next `@test` will not
                # be executed.  The advantage over doing something like
                #     @test success(`...`)
                # is that with
                #    run(`...`)
                #    @test true
                # we can directly see the output of the spawned command, which
                # would be suppressed if using `success`.
                @test true
            end
        end
    end
end
