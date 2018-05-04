using FileIO, Images, ImageCore, JLD
include(Pkg.dir("Knet","data","imagenet.jl"))

@everywhere function myprint(msg::String)
    println(msg); flush(STDOUT)
end

function appendcsv(dir::String, elements...)
    line = join(elements, ",")
    open(dir, "a") do f
        write(f, "$line\n")
    end
end
# 
# @everywhere function readimg(dir, imsize, atype)
#     img = Images.imresize(FileIO.load(dir), imsize)
#     img = atype.(Images.rawview(ImageCore.channelview(img)[1:3, :, :]))
#     return permutedims(img, (2,3,1))
# end
#
# function normalize(x, min, max)
#     oldmin = minimum(x)
#     oldmax = maximum(x)
#     oldrange = oldmax - oldmin
#     newrange = max - min
#
#     scale = (x .- oldmin) ./ oldrange
#     return scale .* newrange .+ min
# end

# function processimgs(basedir::String, bsize::Int, outdir::String;
#                      extension=".webp", imsize=(64, 64), atype=Float32)
#     imgdirs = readdir(basedir)
#     num = length(imgdirs)
#     total = Int(ceil(num/bsize))
#
#     for j = 1:bsize:num
#         upper = min(num,j+bsize)
#         idx = Int(floor(j/bsize)) + 1
#         imgs = SharedArray{atype}(upper-j, imsize[1], imsize[2], 3)
#         info("Reading $idx/$total")
#
#         @sync @parallel for i = j:upper
#             if contains(imgdirs[i], extension)
#                 imgdir = joinpath(basedir, imgdirs[i])
#                 img = readimg(imgdir, imsize, atype)
#                 if length(img) != imsize[1] * imsize[2] * 3
#                     # warn("Grayscale Image: $imgdir")
#                     continue
#                 end
#                 imgidx = i % bsize
#                 if imgidx == 0
#                     imgidx = bsize
#                 end
#                 imgs[imgidx,:,:,:] = img
#             end
#         end
#
#         imgs = Array{Float32}(imgs)
#         info("Saving $idx/$total")
#         filepath = joinpath(outdir, string(idx))*".jld"
#         imgs = normalize(imgs, -1, 1)
#         savetensor(imgs, filepath)
#         info("Done $idx/$total")
#     end
# end

# function normalize4(inp, means, stds)
#     # Saved tensors are normalized between -1 and 1. This is a hacky thing FIXME
#     inp = normalize(inp, 0, 1)
#     for i=1:size(inp, 1) # For each image
#         for c=1:3 # Normalize each channel seperately
#             inp[i,:,:,c] = (inp[i,:,:,c] .- means[c]) ./ stds[c]
#         end
#     end
#     return inp
# end

# function denormalize(inp)
#     return (inp .* 0.5) .+ 0.5
# end

function samplenoise4(size, n, atype)
    """
    Outputs gaussian noise with size (1, 1, size, n)
    """
    return atype(reshape(randn(size, n), 1, 1, size, n))
end

# @everywhere function savetensor(tensor, filepath; name="tensor")
#     JLD.jldopen(filepath, "w") do file
#         write(file, name, tensor)
#     end
# end
#
# function saveimgtensors(basedir, imgs, bsize)
#     total = Int(size(imgs, 1) / bsize)
#     @sync @parallel for k = 1:bsize:size(imgs, 1)
#         lo = k
#         hi = min(k+bsize-1, size(imgs, 1))
#         tensor = imgs[lo:hi,:,:,:]
#         bid = Int(floor(k/bsize))
#         filepath = joinpath(basedir, string(bid))*".jld"
#         savetensor(tensor, filepath)
#         myprint("$bid/$total saved.")
#     end
# end
#
# @everywhere function loadtensor(filepath; name="tensor")
#     JLD.jldopen(filepath, "r") do file
#         read(file, name)
#     end
# end
#
# function loadimgtensors(basedir::String, idxs::Tuple{Int, Int})
#     tensordirs = readdir(basedir)
#     imgs = @sync @parallel (vcat) for dir in tensordirs[idxs[1]:idxs[2]]
#         # myprint("Loading $dir")
#         loadtensor(joinpath(basedir, dir))
#     end
#     # return normalize4(imgs, [0.5, 0.5, 0.5], [0.5, 0.5, 0.5])
#     return imgs
# end
#
# function getnumchunks(dir::String)
#     tensordirs = readdir(dir)
#     return length(tensordirs)
# end

# function minibatch4(X, batchsize, atype; sh=true)
#     """
#     Size of X is (N, w, h, c)
#     Outputs array where each element has size (w, h, c, b)
#     """
#     if sh X = X[shuffle(1:end),:,:,:] end
#     data = Any[]
#     for i=1:batchsize:size(X, 1)
#         limit = min(i+batchsize-1, size(X, 1))
#         minibatch = X[i:limit, :, :, :]
#         per = permutedims(minibatch, [2, 3, 4, 1]) # Examples are last element
#         push!(data, per)
#     end
#     return data
# end

function numparams(paramarr)
    count = 0
    for p in paramarr
        count += length(p)
    end
    return count
end

function generateimgs(generator, params, moments, zsize, atype; n=36, gridsize=(6,6), scale=2.0)
    randz = samplenoise4(zsize, n, atype)
    genimgs = Array(generator(params, moments, randz, training=false)) .+ 0.5 # de-normalize
    images = map(i->reshape(genimgs[:,:,:,i], (64, 64, 3)), 1:n)
    return make_image_grid(images; gridsize=gridsize, scale=scale)
end

function saveimgs(imgs; scale=1.0)
    """
    First dimension is number of elements, n has to be square
    """
    n = size(imgs, 4)
    images = map(i->reshape(imgs[:,:,:,i], (64, 64, 3)), 1:n)
    grid = Int(sqrt(n))
    grid = make_image_grid(images; gridsize=(grid, grid), scale=scale)
    save("images.png", colorview(RGB, grid))
end

function savemodel(path, gparams, gmoments, dparams, dmoments)
    # FIXME: Saving batch normed does not work!
    if dmoments != nothing
        save(path,
             "wd", Array{Float32}.(dparams),
             "wg", Array{Float32}.(gparams),
             "md", convert_moments(dmoments),
             "mg", convert_moments(gmoments))
    else
        save(path,
             "wd", Array{Float32}.(dparams),
             "wg", Array{Float32}.(gparams))
    end
end

function loadmodel(path, atype; moment=true)
    if moment
        @load path wd wg md mg
        wd = atype.(wd)
        wg = atype.(wg)
        return wg, mg, wd, md
    else
        @load path wd wg
        wd = atype.(wd)
        wg = atype.(wg)
        return wg, wd
    end
end


function convert_moments(moments,atype=Array{Float32})
    clone = map(mi->bnmoments(), moments)
    for k = 1:length(clone)
        if moments[k].mean != nothing
            clone[k].mean = convert(atype, moments[k].mean)
        end

        if moments[k].var != nothing
            clone[k].var = convert(atype, moments[k].var)
        end
    end
    return Array{Any,1}(clone)
end
