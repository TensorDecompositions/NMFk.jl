import VegaLite
import VegaDatasets
import DataFrames
import Mads

function plotmap(W::AbstractMatrix, H::AbstractMatrix, fips::AbstractVector, dim::Integer=1; dates=nothing, kw...)
	@assert size(W, 2) == size(H, 1)
	Wa, _, _ = NMFk.normalizematrix_col!(W)
	Ha, _, _ = NMFk.normalizematrix_row!(H)
	# Mads.plotseries(Wa; xaxis=dates)
	if dim == 1
		odim = 2
		so, si = NMFk.signalorder(Wa, odim)
		if dates != nothing
			@assert length(dates) == size(W, 1)
		end
		Mads.plotseries(W[:,so] ./ maximum(W); xaxis=dates, name="Wave")
		ndates = dates != nothing ? dates[si] : dates
		signalid = similar(so)
		for (i,j) in enumerate(so)
			signalid[j] = i
		end
		NMFk.plotmap(Ha, fips, dim, so; signalid=signalid, dates=ndates, kw...)
	else
		odim = 1
		so, si = NMFk.signalorder(Ha, odim)
		if dates != nothing
			@assert length(dates) == size(H, 2)
		end
		Mads.plotseries(H[so,:] ./ maximum(H); xaxis=dates, name="Wave")
		ndates = dates != nothing ? dates[si] : dates
		signalid = similar(so)
		for (i,j) in enumerate(so)
			signalid[j] = i
		end
		NMFk.plotmap(Wa, fips, dim, so; signalid=signalid, dates=ndates, kw...)
	end
end

function plotmap(X::AbstractMatrix, fips::AbstractVector, dim::Integer=1, order=1:size(X, dim); signalid=1:size(X, dim), us10m=VegaDatasets.dataset("us-10m"), goodcounties=trues(length(fips)), dates=nothing, casefilename="", figuredir=".", title::Bool=false, datetext="Date", titletext="", leadingzeros=2, quiet::Bool=false, scheme="redyellowgreen", zmin=0, zmax=1)
	odim = dim == 1 ? 2 : 1
	@assert size(X, odim) == length(fips[goodcounties])
	recursivemkdir(figuredir; filename=false)
	for i in order
		nt = ntuple(k->(k == dim ? i : Colon()), ndims(X))
		df = DataFrames.DataFrame(FIPS=[fips[goodcounties]; fips[.!goodcounties]], Z=[vec(X[nt...]); zeros(sum(.!goodcounties))])
		if typeof(signalid[i]) <: Number
			signalidtext = lpad(signalid[i], leadingzeros, '0')
		else
			signalidtext = signalid[i]
		end
		if title || (dates != nothing && titletext != "")
			ttitle = "$(titletext) $(signalidtext)"
			if dates != nothing
				ttitle *= ": $(datetext): $(dates[i])"
			end
			ltitle = ""
		else
			ttitle = nothing
			if dates != nothing
				ltitle = "$(dates[i])"
			else
				ltitle = "$(titletext) $(signalidtext)"
			end
		end
		p = @VegaLite.vlplot(
			title=ttitle,
			:geoshape,
			width=500, height=300,
			data={
				values=us10m,
				format={
					type=:topojson,
					feature=:counties
				}
			},
			transform=[{
				lookup=:id,
				from={
					data=df,
					key=:FIPS,
					fields=["Z"]
				}
			}],
			projection={type=:albersUsa},
			color={title=ltitle, field="Z", type="quantitative", scale={scheme=scheme, clamp=true, reverse=true, domain=[zmin, zmax]}}
		)
		!quiet && (display(p); println())
		if casefilename != ""
			VegaLite.save(joinpath("$(figuredir)", "$(casefilename)-$(signalidtext).png"), p)
		end
	end
end

function plotmap(X::AbstractVector, fips::AbstractVector; us10m=VegaDatasets.dataset("us-10m"), goodcounties=trues(length(fips)), dates=nothing, casefilename="", figuredir=".", title::Bool=false, datetext="Date", titletext="", leadingzeros=2, quiet::Bool=false, scheme="category10", zmin=0, zmax=1)
	recursivemkdir(figuredir; filename=false)
	@assert length(X) == length(fips)
	nc = length(unique(sort(X))) + 1
	df = DataFrames.DataFrame(FIPS=[fips[goodcounties]; fips[.!goodcounties]], Z=[X; zeros(sum(.!goodcounties))])
	p = @VegaLite.vlplot(
		:geoshape,
		width=500, height=300,
		data={
			values=us10m,
			format={
				type=:topojson,
				feature=:counties
			}
		},
		transform=[{
			lookup=:id,
			from={
				data=df,
				key=:FIPS,
				fields=["Z"]
			}
		}],
		projection={type=:albersUsa},
		color={title="", field="Z", type="ordinal", scale={scheme=vec("#" .*  Colors.hex.(parse.(Colors.Colorant, NMFk.colors), :RGB))[1:nc], reverse=true, domainMax=zmax, domainMin=zmin}}
	)
	!quiet && (display(p); println())
	if casefilename != ""
		VegaLite.save(joinpath("$(figuredir)", "$(casefilename).png"), p)
	end
end