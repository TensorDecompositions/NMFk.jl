import NMFk

a = rand(15)
b = rand(15)
c = rand(15)
[a b c]

import Mads
Mads.plotseries([a b c])

W = [a b c]

H = [1 10 0 0 1; 0 1 1 5 2; 3 0 0 1 5]

X = W * H

Mads.plotseries(X; name="Sensors")

We, He, fitquality, robustness, aic, kopt = NMFk.execute(X, 2:5; save=false, method=:simple);

We[kopt]

He[kopt]

Mads.plotseries(W; title="Original signals")

Mads.plotseries(We[kopt] ./ maximum(We[kopt]; dims=1); title="Reconstructed signals")

NMFk.plotmatrix(H ./ maximum(H); title="Original mixing matrix")

NMFk.plotmatrix(He[kopt] ./ maximum(He[kopt]); title="Reconstructed mixing matrix")
