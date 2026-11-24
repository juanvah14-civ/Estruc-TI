"""Ejecuta las pruebas de MarcosJV.lua con Lua 5.1 (lupa) y compara el marco
del ejemplo 2 contra una solucion independiente (rigidez clasica con FEF de tablas)."""
import os, sys, math
import lupa.lua51 as lua51

here = os.path.dirname(os.path.abspath(__file__))
src = os.path.join(here, "..", "src", "MarcosJV.lua").replace("\\", "/")
test = os.path.join(here, "test_marcos.lua").replace("\\", "/")

L = lua51.LuaRuntime(unpack_returned_tuples=True)
code = open(test, encoding="utf-8").read()
fn = L.execute("return function(...) " + "local f = assert(loadfile('" + test + "')); return f(...) end")
fn(src)

# --- solucion independiente del marco del ejemplo 2 -------------------------
E, A_, I = 2e8, 0.01, 1e-4
nodes = [(0, 0), (0, 4), (6, 4), (6, 0)]
elems = [(0, 1), (1, 2), (2, 3)]
nd = 12
K = [[0.0] * nd for _ in range(nd)]
F = [0.0] * nd
F[3] += 20.0
w = -15.0
for k, (i, j) in enumerate(elems):
    (x1, y1), (x2, y2) = nodes[i], nodes[j]
    Lx = math.hypot(x2 - x1, y2 - y1); c = (x2 - x1) / Lx; s = (y2 - y1) / Lx
    a = E * A_ / Lx; b = 12 * E * I / Lx**3; cc = 6 * E * I / Lx**2; d = 4 * E * I / Lx; e = 2 * E * I / Lx
    kl = [[a,0,0,-a,0,0],[0,b,cc,0,-b,cc],[0,cc,d,0,-cc,e],[-a,0,0,a,0,0],[0,-b,-cc,0,b,-cc],[0,cc,e,0,-cc,d]]
    T = [[0]*6 for _ in range(6)]
    for o in (0, 3):
        T[o][o] = c; T[o][o+1] = s; T[o+1][o] = -s; T[o+1][o+1] = c; T[o+2][o+2] = 1
    kg = [[sum(T[m][p] * kl[m][n] * T[n][q] for m in range(6) for n in range(6)) for q in range(6)] for p in range(6)]
    f0 = [0]*6
    if k == 1:  # carga uniforme en la viga horizontal (local = global)
        f0 = [0, -w*Lx/2, -w*Lx**2/12, 0, -w*Lx/2, w*Lx**2/12]
    mp = [3*i, 3*i+1, 3*i+2, 3*j, 3*j+1, 3*j+2]
    for p in range(6):
        F[mp[p]] -= sum(T[m][p] * f0[m] for m in range(6))
        for q in range(6):
            K[mp[p]][mp[q]] += kg[p][q]
free = [3, 4, 5, 6, 7, 8]
Af = [[K[i][j] for j in free] for i in free]; bf = [F[i] for i in free]
n = len(free)
for col in range(n):
    for r in range(col + 1, n):
        f = Af[r][col] / Af[col][col]
        for cc2 in range(col, n): Af[r][cc2] -= f * Af[col][cc2]
        bf[r] -= f * bf[col]
x = [0] * n
for r in range(n - 1, -1, -1):
    x[r] = (bf[r] - sum(Af[r][cc2] * x[cc2] for cc2 in range(r + 1, n))) / Af[r][r]
d = [0.0] * nd
for k2, i in enumerate(free): d[i] = x[k2]
R = [sum(K[i][j] * d[j] for j in range(nd)) - F[i] for i in range(nd)]
ref = x + [R[0], R[1], R[2], R[11]]
got = list(L.globals().PORTAL.values())
bad = 0
for g, r in zip(got, ref):
    if abs(g - r) > 1e-8 * max(1, abs(r)):
        bad += 1; print("DIFERENCIA marco:", g, r)
print("Comparacion independiente del marco:", "OK" if bad == 0 else f"{bad} diferencias")
print("  Rx1=%.4f Ry1=%.4f M1=%.4f M4=%.4f" % (R[0], R[1], R[2], R[11]))
