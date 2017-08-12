"Execute NMFk analysis for a range of number of sources"
function execute(X::Matrix, range::UnitRange{Int}, nNMF::Integer=10; kw...)
	maxsources = maximum(collect(range))
	W = Array{Array{Float64, 2}}(maxsources)
	H = Array{Array{Float64, 2}}(maxsources)
	fitquality = Array{Float64}(maxsources)
	robustness = Array{Float64}(maxsources)
	aic = Array{Float64}(maxsources)
	for numsources in range
		W[numsources], H[numsources], fitquality[numsources], robustness[numsources], aic[numsources] = NMFk.execute(X, numsources, nNMF; kw...)
	end
	return W, H, fitquality, robustness, aic
end

"Execute NMFk analysis for a given number of sources"
function execute(X::Matrix, nk::Integer, nNMF::Integer=10; casefilename::String="", serial::Bool=false, save::Bool=true, load::Bool=false, kw...)
	runflag = true
	if load && casefilename != ""
		filename = "$casefilename-$nk-$nNMF.jld"
		if isfile(filename)
			W, H, fitquality, robustness, aic = JLD.load(filename, "W", "H", "fit", "robustness", "aic")
			save = false
			runflag = false
		end
	end
	if runflag
		W, H, fitquality, robustness, aic = NMFk.execute_run(X, nk, nNMF; kw...)
	end
	println("Sources: $(@sprintf("%2d", nk)) Fit: $(@sprintf("%12.7g", fitquality)) Silhouette: $(@sprintf("%12.7g", robustness)) AIC: $(@sprintf("%12.7g", aic))")
	if save && casefilename != ""
		filename = "$casefilename-$nk-$nNMF.jld"
		JLD.save(filename, "W", W, "H", H, "fit", fitquality, "robustness", robustness, "aic", aic)
	end
	return W, H, fitquality, robustness, aic
end

"Execute NMFk analysis for a given number of sources in serial or parallel"
function execute_run(X::Matrix, nk::Int, nNMF::Int; clusterweights::Bool=false, acceptratio::Number=1, acceptfactor::Number=Inf, quiet::Bool=true, best::Bool=true, transpose::Bool=false, mixtures::Bool=true, serial::Bool=false, deltas::Matrix{Float32}=Array{Float32}(0, 0), ratios::Union{Void,Array{Float32, 2}}=nothing, method::Symbol=:nmf, nmfalgorithm::Symbol=:multdiv, kw...)
	# ipopt=true is equivalent to mixmatch = true && mixtures = false
	!quiet && info("NMFk analysis of $nNMF NMF runs assuming $nk sources ...")
	indexnan = isnan.(X)
	if any(indexnan) && (!ipopt || !mixmatch)
		warn("The analyzed matrix has missing entries; NMF multiplex algorithm cannot be used; Ipopt minimization will be performed")
		ipopt = true
	end
	numobservations = length(vec(X[map(!, indexnan)]))
	if method == :multdiv
		method = :nmf
		nmfalgorithm = :multdiv
	elseif method == :multmse
		method = :nmf
		nmfalgorithm = :multmse
	elseif method == :alspgrad
		method = :nmf
		nmfalgorithm = :alspgrad
	end
	if !quiet
		if method == :mixmatch
			println("MixMatch ...")
		elseif method == :matchwaterdeltas
			println("MixMatchDeltas ...")
		elseif method == :ipopt
			println("Ipopt ...")
		elseif method == :nmf
			if nmfalgorithm == :multdiv
				println("NMF Multiplicative update using divergence ...")
			elseif nmfalgorithm == :multmse
				println("NMF Multiplicative update using mean-squared-error ...")
			elseif nmfalgorithm == :alspgrad
				println("NMF Alternate Least Square using Projected Gradient Descent ...")
			end
		elseif method == :sparse
			println("Sparse NMF ...")
		elseif method == :simple
			println("Simple NMF multiplicative ...")
		end
	end
	if transpose
		nC, nP = size(X) # number of observed components/transients, number of observation points
	else
		nP, nC = size(X) # number of observation points,  number of observed components/transients
	end
	# nRC = sizeof(deltas) == 0 ? nC : nC + size(deltas, 2)
	if nprocs() > 1 && !serial
		r = pmap(i->(NMFk.execute_singlerun(X, nk; quiet=true, best=best, mixtures=mixtures, transpose=transpose, deltas=deltas, ratios=ratios, method=method, nmfalgorithm=nmfalgorithm, kw...)), 1:nNMF)
		WBig = Vector{Matrix}(nNMF)
		HBig = Vector{Matrix}(nNMF)
		for i in 1:nNMF
			WBig[i] = r[i][1]
			HBig[i] = r[i][2]
		end
		objvalue = map(i->convert(Float32, r[i][3]), 1:nNMF)
	else
		WBig = Vector{Matrix}(0)
		HBig = Vector{Matrix}(0)
		objvalue = Array{Float64}(nNMF)
		for i = 1:nNMF
			W, H, objvalue[i] = NMFk.execute_singlerun(X, nk; quiet=true, best=best, mixtures=mixtures, transpose=transpose, deltas=deltas, ratios=ratios, method=method, nmfalgorithm=nmfalgorithm, kw...)
			push!(WBig, W)
			push!(HBig, H)
		end
	end
	!quiet && println("Best  objective function = $(minimum(objvalue))")
	!quiet && println("Worst objective function = $(maximum(objvalue))")
	bestIdx = indmin(objvalue)
	Wbest = WBig[bestIdx]
	Hbest = HBig[bestIdx]
	println()
	if acceptratio < 1
		ratind = sortperm(objvalue) .<= (nNMF * acceptratio)
		println("NMF solutions removed based on an acceptance ratio: $(sum(ratind)) out of $(nNMF) solutions")
		!quiet && (println("Good solutions based on an acceptance ratio: $(objvalue[ratind])"))
	else
		ratind = trues(nNMF)
	end
	if acceptfactor < Inf
		cutoff = objvalue[bestIdx] * acceptfactor
		cutind = objvalue.<cutoff
		println("NMF solutions removed based on an acceptance factor: $(sum(cutind)) out of $(nNMF) solutions")
		!quiet && (println("Good solutions based on an acceptance factor: $(objvalue[cutind])"))
	else
		cutind = trues(nNMF)
	end
	solind = ratind & cutind
	if solind != ratind && solind != cutind
		println("NMF solutions removed based on acceptance criteria: $(sum(solind)) out of $(nNMF) solutions")
		!quiet && (println("Good solutions based on acceptance criteria: $(objvalue[solind])"))
	end
	if solind != ratind || solind != cutind
		println("OF: min $(minimum(objvalue)) max $(maximum(objvalue)) mean $(mean(objvalue)) std $(std(objvalue))")
	end
	println("OF: min $(minimum(objvalue[solind])) max $(maximum(objvalue[solind])) mean $(mean(objvalue[solind])) std $(std(objvalue[solind]))")
	Xe = Wbest * Hbest
	println("Worst correlation by columns: $(minimum(map(i->cor(X[i,:], Xe[i,:]), 1:size(X,1))))")
	println("Worst correlation by rows: $(minimum(map(i->cor(X[:,i], Xe[:,i]), 1:size(X,2))))")
	minsilhouette = 1
	if nk > 1
		if clusterweights
			clusterassignments, M = NMFk.clusterSolutions(WBig[solind], clusterweights) # cluster based on the W
		else
			clusterassignments, M = NMFk.clusterSolutions(HBig[solind], clusterweights) # cluster based on the sources
		end
		if !quiet
			info("Cluster assignments:")
			display(clusterassignments)
			info("Cluster centroids:")
			display(M)
		end
		Wa, Ha, clustersilhouettes = NMFk.finalize(WBig[solind], HBig[solind], clusterassignments, clusterweights)
		minsilhouette = minimum(clustersilhouettes)
		if !quiet
			info("Silhouettes for each of the $nk sources:" )
			display(clustersilhouettes')
			println("Mean silhouette = ", mean(clustersilhouettes))
			println("Min  silhouette = ", minimum(clustersilhouettes))
		end
	else
		Wa, Ha = NMFk.finalize(WBig[solind], HBig[solind])
	end
	if best
		Wa = Wbest
		Ha = Hbest
	end
	if sizeof(deltas) == 0
		if transpose
			E = X' - Wa * Ha
		else
			E = X - Wa * Ha
		end
		E[isnan.(E)] = 0
		phi_final = sum(E.^2)
	else
		Ha_conc = Ha[:,1:nC]
		Ha_deltas = Ha[:,nC+1:end]
		estdeltas = NMFk.computedeltas(Wa, Ha_conc, Ha_deltas, deltaindices)
		if transpose
			E = X' - Wa * Ha_conc
		else
			E = X - Wa * Ha_conc
		end
		E[isnan.(E)] = 0
		id = !isnan.(deltas)
		phi_final = sum(E.^2) + sum((deltas[id] .- estdeltas[id]).^2)
	end
	if !quiet && typeof(ratios) != Void
		ratiosreconstruction = 0
		for (j, c1, c2) in zip(1:length(ratioindices[1,:]), ratioindices[1,:], ratioindices[2,:])
			for i = 1:nP
				s1 = 0
				s2 = 0
				for k = 1:nk
					s1 += Wa[i, k] * Ha[k, c1]
					s2 += Wa[i, k] * Ha[k, c2]
				end
				ratiosreconstruction += ratiosweight * (s1/s2 - ratios[i, j])^2
			end
		end
		println("Ratio reconstruction = $ratiosreconstruction")
		phi_final += ratiosreconstruction
	end
	numparameters = *(collect(size(Wa))...) + *(collect(size(Ha))...)
	if method == :mixmatch && mixtures
		numparameters -= size(Wa)[1]
	end
	# numparameters = numbuckets # this is wrong
	# dof = numobservations - numparameters # this is correct, but we cannot use because we may get negative DoF
	# dof = maximum(range) - numparameters + 1 # this is a hack to make the dof positive.
	# dof = dof < 0 ? 0 : dof
	# sml = dof + numobservations * (log(fitquality[numbuckets]/dof) / 2 + 1.837877)
	# aic[numbuckets] = sml + 2 * numparameters
	aic = 2 * numparameters + numobservations * log(phi_final/numobservations)
	!quiet && println("Objective function = ", phi_final, " Max error = ", maximum(E), " Min error = ", minimum(E) )
	return Wa, Ha, phi_final, minsilhouette, aic
end

"Execute single NMF run"
function execute_singlerun(x...; kw...)
	if restart
		return execute_singlerun_r3(x...; kw...)
	else
		return execute_singlerun_compute(x...; kw...)
	end
end

"Execute single NMF run without restart"
function execute_singlerun_compute(X::Matrix, nk::Int; quiet::Bool=true, ratios::Union{Void,Array{Float32, 2}}=nothing, ratioindices::Union{Array{Int,1},Array{Int,2}}=Array{Int}(0, 0), deltas::Matrix{Float32}=Array{Float32}(0, 0), deltaindices::Vector{Int}=Array{Int}(0), best::Bool=true, normalize::Bool=false, scale::Bool=false, mixtures::Bool=true, maxiter::Int=10000, tol::Float64=1.0e-19, regularizationweight::Float32=convert(Float32, 0), ratiosweight::Float32=convert(Float32, 1), weightinverse::Bool=false, transpose::Bool=false, sparsity::Number=5, sparse_cf::Symbol=:kl, sparse_div_beta::Number=-1, method::Symbol=:nmf, nmfalgorithm::Symbol=:multdiv, kw...)
	if scale
		if transpose
			Xn, Xmax = NMFk.scalematrix(X)
			Xn = Xn'
		else
			Xn, Xmax = NMFk.scalematrix(X)
		end
	else
		if transpose
			Xn = X'
		else
			Xn = X
		end
	end
	if method == :sparse
		W, H, (_, objvalue, _) = NMFk.NMFsparse(Xn, nk; maxiter=maxiter, tol=tol, sparsity=sparsity, cf=sparse_cf, div_beta=sparse_div_beta, quiet=quiet, kw...)
	elseif method == :mixmatch
		if sizeof(deltas) == 0
			W, H, objvalue = NMFk.mixmatchdata(Xn, nk; ratios=ratios, ratioindices=ratioindices, random=true, mixtures=mixtures, normalize=normalize, scale=false, maxiter=maxiter, regularizationweight=regularizationweight, weightinverse=weightinverse, ratiosweight=ratiosweight, quiet=quiet, kw...)
		else
			W, Hconc, Hdeltas, objvalue = NMFk.mixmatchdata(Xn, deltas, deltaindices, nk; random=true, normalize=normalize, scale=false, maxiter=maxiter, regularizationweight=regularizationweight, weightinverse=weightinverse, ratiosweight=ratiosweight, quiet=quiet, kw...)
			H = [Hconc Hdeltas]
		end
	elseif method == :matchwaterdeltas
		W, H, objvalue = NMFk.mixmatchwaterdeltas(Xn, nk; random=true, maxiter=maxiter, regularizationweight=regularizationweight, kw...)
	elseif method == :ipopt
		W, H, objvalue = NMFk.ipopt(X, nk; random=true, normalize=normalize, scale=false, maxiter=maxiter, regularizationweight=regularizationweight, weightinverse=weightinverse, quiet=quiet, kw...)
	elseif method == :simple
		W, H, objvalue = NMFk.NMFmultiplicative(Xn, nk; quiet=quiet, tol=tol, maxiter=maxiter, kw...)
		E = X - W * H
		objvalue = sum(E.^2)
		# objvalue = vecnorm(X - W * H)
	elseif method == :nmf
		W, H = NMF.randinit(Xn, nk)
		if nmfalgorithm == :multdiv
			nmf_result = NMF.solve!(NMF.MultUpdate{typeof(X[1,1])}(obj=:mse, maxiter=maxiter, tol=tol), Xn, W, H)
		elseif nmfalgorithm == :multmse
			nmf_result = NMF.solve!(NMF.MultUpdate{typeof(X[1,1])}(obj=:div, maxiter=maxiter, tol=tol), Xn, W, H)
		elseif nmfalgorithm == :alspgrad
			nmf_result = NMF.solve!(NMF.ALSPGrad{typeof(X[1,1])}(maxiter=maxiter, tol=tol, tolg=tol*100), Xn, W, H)
		end
		!quiet && println("NMF Converged: " * string(nmf_result.converged))
		W = nmf_result.W
		H = nmf_result.H
		objvalue = nmf_result.objvalue
	else
		error("Unknown method: $method")
	end
	if scale
		if transpose
			W = NMFk.descalematrix(W, Xmax')
			E = X' - W * H
		else
			H = NMFk.descalematrix(H, Xmax)
			E = X - W * H
		end
		objvalue = sum(E.^2)
	end
	!quiet && println("Objective function = $(objvalue)")
	if method != :mixmatch || method != :matchwaterdeltas
		total = sum(W, 1)
		W ./= total
		H .*= total'
	end
	return W, H, objvalue
end

function NMFrun(X::Matrix, nk::Integer; maxiter::Integer=maxiter, normalize::Bool=true)
	W, H = NMF.randinit(X, nk, normalize = true)
	NMF.solve!(NMF.MultUpdate(obj = :mse, maxiter=maxiter), X, W, H)
	if normalize
		total = sum(W, 1)
		W ./= total
		H .*= total'
	end
	return W, H
end
