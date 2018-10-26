#== # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Description
#
#   WDCFILES.txt
#
#   The WDC files contains the Kp and Ap indices.
#
#   For more information, see:
#
#       https://www.gfz-potsdam.de/en/kp-index/
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # ==#

################################################################################
#                       Private Structures and Variables
################################################################################

"""
Structure to store the interpolations of the data in WDC files.

# Fields

* `Kp`: Kp index.
* `Ap`: Ap index.

"""
struct _WDC_Structure
    Kp::AbstractExtrapolation
    Ap::AbstractExtrapolation
end

# Remote files: *.wdc
#
# This set will be configured in the function `init_space_indices()`.
_wdcfiles = RemoteFileSet(".wdc files", Dict{Symbol,RemoteFile}())

# Optional variable that will store the WDC data.
@OptionalData _wdc_data _WDC_Structure "Run `init_space_indices()` to initialize the space indices structures."

################################################################################
#                               Public Functions
################################################################################

#                                   Getters
# ==============================================================================

"""
    function get_Kp(JD::Number)

Return the Kp index at Julian Day `JD`.

"""
function get_Kp(JD::Number)
    Kp_day = get(SatelliteToolbox._wdc_data).Kp(JD)

    # Get the hour of the day and return the appropriate Kp.
    y, m, d, h, min, sec = JDtoDate(JD)

    return Kp_day[ floor(Int, h/3) + 1 ]
end

"""
    function get_Ap(JD::Number; mean::Tuple{Int} = (), daily = false)

Return the Ap index.

If `mean` is a tuple of two integers `(hi, hf)`, then the average between `hi`
and `hf` previous hours will be computed.

If `mean` is empty and `daily` is `true`, then the day average will be computed.

If `mean` keyword is empty, and `daily` keyword is `false`, then the Ap at
Julian day `JD` will be computed.

By default, `mean` is empty and `daily` is `false`.

"""
function get_Ap(JD::Number; mean::Tuple = (), daily = false)
    # Check if we must compute the mean of previous hours.
    if isempty(mean)
        Ap_day = get(SatelliteToolbox._wdc_data).Ap(JD)

        # Check if we must compute the daily mean.
        if daily
            return sum(Ap_day)/8
        else
            # Get the hour of the day and return the appropriate Ap.
            y, m, d, h, min, sec = JDtoDate(JD)

            return Ap_day[ floor(Int, h/3) + 1 ]
        end
    else
        # Check the inputs.
        (length(mean) != 2) && @error "The keyword `mean` must be empty or a tuple with exactly 2 integers."
        hi = mean[1]
        hf = mean[2]
        (hi > hf) && @error "The first argument of the keyword `mean` must be lower than the second."

        # Assemble the vector with the previous hours that will be averaged.
        hv = hi:3:hf

        # Compute the mean.
        Ap_sum = 0
        for h in hv
            Ap_sum += get_Ap(JD - h/24; mean = (), daily = false)
        end

        return Ap_sum/length(hv)
    end
end

################################################################################
#                              Private Functions
################################################################################

function _parse_wdcfiles(filepaths::Vector{String}, years::Vector{Int})
    # Allocate the raw data.
    JD = Float64[]
    Kp = Vector{Float64}[]
    Ap = Vector{Int}[]

    for (filepath, year) in zip(filepaths, years)

        open(filepath) do file
            # Read each line.
            for ln in eachline(file)
                # Get the Julian Day.
                month = parse(Int, ln[3:4])
                day   = parse(Int, ln[5:6])

                # The JD of the data will be computed at noon. Hence, we will be
                # able to use the nearest-neighbor algorithm in the
                # interpolations.
                JD_k  = DatetoJD(year, month, day, 12, 0, 0)

                # Get the vector of Kps and Aps.
                Ap_k = zeros(Int,    8)
                Kp_k = zeros(Float64,8)

                for i = 1:8
                    Kp_k[i] = parse(Int, ln[2(i-1) + 13:2(i-1) + 14])/10
                    Ap_k[i] = parse(Int, ln[3(i-1) + 32:3(i-1) + 34])
                end

                # Add data to the vector.
                push!(JD, JD_k)
                push!(Kp, Kp_k)
                push!(Ap, Ap_k)
            end
        end
    end

    # Create the interpolations for each parameter.
    knots    = (JD,)

    # Create the interpolations.
    itp_Kp = extrapolate(interpolate(knots, Kp, Gridded(Constant())), Flat())
    itp_Ap = extrapolate(interpolate(knots, Ap, Gridded(Constant())), Flat())

    _WDC_Structure(itp_Kp, itp_Ap)
end

function _prepare_wdc_remote_files(oldest_year::Number)
    # Get the current year.
    current_year = year(now())

    # If `oldest_year` is greater than current year, then consider only the
    # current year.
    (oldest_year > current_year) && (oldest_year = current_year)

    # For the current year, we must update the remote file every day. Otherwise,
    # we do not need to update at all.
    for y = oldest_year:current_year
		filename = "kp$y"
        sym = Symbol(filename)
        file_y = @RemoteFile("ftp://ftp.gfz-potsdam.de/pub/home/obs/kp-ap/wdc/$filename.wdc",
                             file="$filename.wdc",
                             updates= (y == current_year) ? :daily : :never)

        merge!(_wdcfiles.files, Dict(sym => file_y))
    end

    nothing
end
