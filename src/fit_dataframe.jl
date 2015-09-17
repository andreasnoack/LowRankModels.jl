import DataFrames: DataFrame, DataArray, isna, dropna, array, ncol, convert, NA

export GLRM, observations, expand_categoricals!, NaNs_to_NAs

max_ordinal_levels = 9

# TODO: identify categoricals automatically from PooledDataArray columns

function GLRM(df::DataFrame, k::Int;
              losses = None, rx = QuadReg(.01), ry = QuadReg(.01),
              offset = true, scale = true)
    if losses == None # if losses not specified, identify ordinal, boolean and real columns
        reals, real_losses = get_reals(df)
        bools, bool_losses = get_bools(df)
        ordinals, ordinal_losses = get_ordinals(df)
        A = [df[reals] df[bools] df[ordinals]]
        labels = [names(df)[reals], names(df)[bools], names(df)[ordinals]]
        losses = [real_losses, bool_losses, ordinal_losses]
    else # otherwise require one loss function per column
        A = df
        ncol(df)==length(losses) ? labels = names(df) : error("please input one loss per column of dataframe")
    end
    # identify which entries in data frame have been observed (ie are not N/A)
    obs = observations(A)
    # initialize X and Y
    X = randn(k,size(A,1))
    Y = randn(k,size(A,2))
    # form model
    glrm = GLRM(df2array(A), losses, rx, ry, k, obs=obs, X=X, Y=Y, offset=offset, scale=scale)
    return glrm, labels
end

function observations(df::DataFrame)
    obs = (Int, Int)[]
    m,n = size(df)
    for j=1:n # follow column-major order. First element of index in innermost loop
        for i=1:m
            if !isna(df[i,j])
                push!(obs,(i,j))
            end
        end
    end
    return obs
end

function df2array(df::DataFrame, z::Number)
    A = zeros(size(df))
    for i=1:size(A,2)
        if typeof(df[i]) == Bool
            A[:,i] = convert(Array, (2*df[i]-1), z)
        else
            A[:,i] = convert(Array, df[i], z)
        end            
    end
    return A
end
df2array(df::DataFrame) = df2array(df, 0)

function get_reals(df::DataFrame)
    m,n = size(df)
    reals = [typeof(df[i])<:DataArray{Float64,1} for i in 1:n]
    n1 = sum(reals)
    losses = Array(Loss,n1)
    for i=1:n1
        losses[i] = QuadLoss()
    end
    return reals, losses
end

function get_bools(df::DataFrame)
    m,n = size(df)
    bools = [isa(df[i], DataArray{Bool,1}) for i in 1:n]
    n1 = sum(bools)
    losses = Array(Loss,n1)
    for i=1:n1
        losses[i] = HingeLoss()
    end
    return bools, losses
end

function get_ordinals(df::DataFrame)
    m,n = size(df)
    # there must be a better way to check types...
    ordinals = [(isa(df[i], DataArray{Int,1}) || 
                 isa(df[i], DataArray{Int32,1}) || 
                 isa(df[i], DataArray{Int64,1})) for i in 1:n]
    nord = sum(ordinals)
    ord_idx = (1:size(df,2))[ordinals]
    maxs = zeros(nord,1)
    mins = zeros(nord,1)
    for i in 1:nord
        col = df[ord_idx[i]]
        try
            maxs[i] = maximum(dropna(col))
            mins[i] = minimum(dropna(col))
        end
    end

    # set losses and regularizers
    losses = Array(Loss,nord)
    for i=1:nord
        losses[i] = OrdinalHinge(mins[i],maxs[i])
    end
    return ordinals, losses
end

function expand_categoricals!(df::DataFrame,categoricals::Array)
    categoricalidxs = map(y->df.colindex[y], categoricals)
    # create one boolean column for each level of categorical column
    for col in categoricals
        levels = sort(unique(df[:,col]))
        for level in levels
            if !isna(level)
                colname = symbol(string(col)*"="*string(level))
                df[colname] = (df[:,col] .== level)
            end
        end
    end
    # remove the original categorical columns
    return df[:, filter(x->(!(x in categoricals)), names(df))]
end

# convert NaNs to NAs
function NaNs_to_NAs(df::DataFrame)
    m,n = size(df)
    for j=1:n # follow column-major order. First element of index in innermost loop
        for i=1:m
            if isnan(df[i,j])
                df[i,j] = NA
            end
        end
    end
    return df
end