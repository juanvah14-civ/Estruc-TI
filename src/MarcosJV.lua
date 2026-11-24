--[[==================================================================
  Estruc-TI (antes MARCOS 2D) - Analisis de marcos planos por rigidez
  Para TI-Nspire CX II / CX II CAS  (Lua, platform.apilevel 2.4)

  Version 1.2 (cargas incognitas: P, w... y despeje de incognitas)
  Version 1.1 (nueva interfaz + ecuaciones por tramo)
  Basado en la app FEES del Ing. Sergio Lobo Aguilar (UCR).
  Desarrollado con ayuda de la IA Claude (Anthropic).
  (c) 2026 Juan Vargas. Todos los derechos reservados.
  Autor: Juan Vargas - Estudiante de Ingenieria Civil

  Resuelve marcos, vigas y armaduras planas (isostaticos e
  hiperestaticos) y entrega reacciones, desplazamientos y los
  diagramas N, V, M, rotacion (theta) y deflexion (delta).

  Convencion de signos de ENTRADA (ejes globales):
     +X derecha, +Y arriba, momento antihorario (+).
     Izquierda, abajo y horario son NEGATIVOS.
  Convencion de RESULTADOS internos (eje local x' de i -> j):
     N(+) traccion, V(+) = suma de fuerzas en +y' a la izquierda,
     M(+) comprime la fibra +y' (en una viga i->j a la derecha:
     M+ = "sonrisa"). theta y delta en ejes locales del elemento.
====================================================================]]
platform.apilevel = "2.4"

local floor, ceil, abs, sqrt, max, min = math.floor, math.ceil, math.abs, math.sqrt, math.max, math.min
local HUGE = math.huge
local W, H = 318, 212
local AUTOR = "Juan Vargas"
local VERSION = "1.2"

------------------------------------------------------------------
-- Unidades y catalogos
------------------------------------------------------------------
local FU  = {"kN", "N", "kgf", "tf", "lbf", "kip"}
local FSI = {1000, 1, 9.80665, 9806.65, 4.4482216152605, 4448.2216152605}
local LU  = {"m", "cm", "mm", "ft", "in"}
local LSI = {1, 0.01, 0.001, 0.3048, 0.0254}

local SUP = {
  {n = "Libre",                   s = "",      r = {0, 0, 0}},
  {n = "Empotrado",               s = "Emp",   r = {1, 1, 1}},
  {n = "Articulado (fijo)",       s = "Art",   r = {1, 1, 0}},
  {n = "Rodillo (se mueve en X)", s = "RodX",  r = {0, 1, 0}},
  {n = "Rodillo (se mueve en Y)", s = "RodY",  r = {1, 0, 0}},
  {n = "Deslizadera X (sin giro)", s = "DesX", r = {0, 1, 1}},
  {n = "Deslizadera Y (sin giro)", s = "DesY", r = {1, 0, 1}},
}
local SUPN = {}
for i, s in ipairs(SUP) do SUPN[i] = s.n end

local LT = {"Distribuida", "Puntual", "Momento"}
local LD = {"Y global", "X global", "Perpendicular (y')", "Axial (x')",
            "Y global proyectada", "X global proyectada"}
local LDS = {"Y", "X", "y'", "x'", "Yp", "Xp"}
local SINO = {"No", "Si"}

local QN = {"N", "V", "M", "θ", "δ", "u"}
local QL = {"Normal N", "Cortante V", "Momento M", "Rotacion θ", "Flecha δ (y')", "Desp. axial u (x')"}

------------------------------------------------------------------
-- Modelo
------------------------------------------------------------------
local M, RES

local function newModel()
  return {fu = 1, lu = 1, ax = 1, ms = 1,
          nodes = {}, secs = {{E = 2e8, A = 0.01, I = 1e-4}},
          elems = {}, nl = {}, el = {}}
end

local function nd(x, y, sup)
  return {x = x, y = y, sup = sup or 1, sx = 0, sy = 0, sr = 0, kx = 0, ky = 0, kr = 0}
end

local function fixModel()
  local d = newModel()
  for _, k in ipairs({"fu", "lu", "ax", "ms"}) do if type(M[k]) ~= "number" then M[k] = d[k] end end
  for _, k in ipairs({"nodes", "secs", "elems", "nl", "el"}) do if type(M[k]) ~= "table" then M[k] = d[k] end end
  if #M.secs == 0 then M.secs = d.secs end
  for _, p in ipairs(M.nodes) do
    for _, k in ipairs({"x", "y", "sx", "sy", "sr", "kx", "ky", "kr"}) do p[k] = p[k] or 0 end
    p.sup = p.sup or 1
  end
  for _, e in ipairs(M.elems) do e.s = e.s or 1; e.hi = e.hi or 1; e.hj = e.hj or 1 end
  for _, l in ipairs(M.nl) do l.fx = l.fx or 0; l.fy = l.fy or 0; l.m = l.m or 0 end
  if type(M.symv) ~= "table" then M.symv = {} end
  for _, l in ipairs(M.el) do
    l.t = l.t or 1; l.d = l.d or 1; l.v1 = l.v1 or 0; l.v2 = l.v2 or 0; l.a = l.a or 0; l.b = l.b or 0
  end
end

M = newModel()

local function uF() return FU[M.fu] end
local function uL() return LU[M.lu] end
local function uM() return uF() .. "·" .. uL() end
local function uW() return uF() .. "/" .. uL() end
local function uE() return uF() .. "/" .. uL() .. "²" end
local function uA() return uL() .. "²" end
local function uI() return uL() .. "^4" end
local function uK() return uF() .. "/" .. uL() end
local function uKr() return uF() .. "·" .. uL() .. "/rad" end
local function uRad() return "rad" end
local QU = {uF, uF, uM, uRad, uL, uL}

------------------------------------------------------------------
-- Formato de numeros
------------------------------------------------------------------
local function fmt(v, tol, dig)
  if v == nil then return "-" end
  if v ~= v then return "NaN" end
  if tol and abs(v) < tol then v = 0 end
  if abs(v) < 1e-14 then return "0" end
  local s = string.format("%." .. (dig or 5) .. "g", v)
  s = s:gsub("e%+0*(%d)", "E%1"):gsub("e%-0*(%d)", "E-%1")
  return s
end

local function numStr(v)
  if type(v) ~= "number" then return "0" end
  local s = string.format("%.10g", v)
  s = s:gsub("e%+0*(%d)", "E%1"):gsub("e%-0*(%d)", "E-%1")
  return s
end

local function parseNum(t)
  if not t then return nil end
  local s = t:gsub("−", "-"):gsub("ᴇ", "e"):gsub("E", "e"):gsub("%s", "")
  if s == "" then return nil end
  local v = tonumber(s)
  if v then return v end
  if math.eval then
    local ok, r = pcall(math.eval, t)
    if ok and type(r) == "number" then return r end
  end
  return nil
end

------------------------------------------------------------------
-- CARGAS INCOGNITAS (v1.2)
--   Un valor de carga puede ser un numero o una forma lineal
--   {c = constante, s = {P = coef, w = coef, ...}}  (c + coef*P + ...)
--   El calculo se hace con valores numericos de las incognitas (ENV)
--   y, por superposicion, se obtienen los resultados en funcion de ellas.
------------------------------------------------------------------
local ENV = {}

local function Lval(v, env)
  if type(v) ~= "table" then return v or 0 end
  local s = v.c or 0
  env = env or ENV
  for k, a in pairs(v.s or {}) do s = s + a * (env[k] or 0) end
  return s
end

local LvalE = Lval

local function Lscale(v, f)
  if type(v) ~= "table" then return v * f end
  local r = {c = (v.c or 0) * f, s = {}}
  for k, a in pairs(v.s or {}) do r.s[k] = a * f end
  return r
end

-- Interpreta expresiones lineales: P, -2P, P/2, 3+0.5*w, 2(P+1), 1.5E3...
local function Lparse(t)
  if not t then return nil end
  local s = t:gsub("−", "-"):gsub("ᴇ", "E"):gsub("·", "*"):gsub("×", "*"):gsub("%s", "")
  if s == "" then return nil end
  local pos = 1
  local function peek() return s:sub(pos, pos) end
  local function K(n) return {c = n, s = {}} end
  local function isK(a) for _, v in pairs(a.s) do if v ~= 0 then return false end end return true end
  local function scal(a, f) local r = K(a.c * f); for k, v in pairs(a.s) do r.s[k] = v * f end; return r end
  local function add(a, b, sg)
    local r = K(a.c + sg * b.c)
    for k, v in pairs(a.s) do r.s[k] = v end
    for k, v in pairs(b.s) do r.s[k] = (r.s[k] or 0) + sg * v end
    return r
  end
  local function mul(a, b)
    if isK(a) then return scal(b, a.c) elseif isK(b) then return scal(a, b.c) end
    error("no lineal")
  end
  local expr
  local function factor()
    local ch = peek()
    if ch == "+" then pos = pos + 1; return factor() end
    if ch == "-" then pos = pos + 1; return scal(factor(), -1) end
    local base
    if ch == "(" then
      pos = pos + 1
      base = expr()
      if peek() ~= ")" then error("falta )") end
      pos = pos + 1
    else
      local a, b = s:find("^%d*%.?%d+[eE][%+%-]?%d+", pos)
      if not a then a, b = s:find("^%d+%.?%d*", pos) end
      if not a then a, b = s:find("^%.%d+", pos) end
      if a then
        base = K(tonumber(s:sub(a, b))); pos = b + 1
      else
        a, b = s:find("^[%a_][%w_]*", pos)
        if not a then error("simbolo") end
        local name = s:sub(a, b); pos = b + 1
        if name == "pi" then base = K(math.pi) else base = K(0); base.s[name] = 1 end
      end
    end
    if peek() == "^" then
      pos = pos + 1
      local ex = factor()
      if not (isK(base) and isK(ex)) then error("no lineal") end
      base = K(base.c ^ ex.c)
    end
    return base
  end
  local function term()
    local a = factor()
    while true do
      local ch = peek()
      if ch == "*" or ch == "/" then
        pos = pos + 1
        local b = factor()
        if ch == "/" then
          if not isK(b) or b.c == 0 then error("division") end
          a = scal(a, 1 / b.c)
        else
          a = mul(a, b)
        end
      elseif ch ~= "" and ch:match("[%w_%.%(]") then
        a = mul(a, factor())            -- multiplicacion implicita: 2P, 3(P+1)
      else
        break
      end
    end
    return a
  end
  expr = function()
    local a = term()
    while peek() == "+" or peek() == "-" do
      local ch = peek(); pos = pos + 1
      a = add(a, term(), ch == "+" and 1 or -1)
    end
    return a
  end
  local ok, r = pcall(function()
    local v = expr()
    if pos <= #s then error("resto") end
    return v
  end)
  if ok then
    local out, any = {c = r.c, s = {}}, false
    for k, v in pairs(r.s) do if v ~= 0 then out.s[k] = v; any = true end end
    if not any then return r.c end
    return out
  end
  return parseNum(t)       -- funciones de la calculadora: √(2), sin(30)...
end

-- Texto de una forma lineal: "30 + 0.66667P - 2w"
local function Lstr(v, tol, dig)
  if type(v) ~= "table" then return fmt(v, tol, dig) end
  local names = {}
  for k in pairs(v.s or {}) do names[#names + 1] = k end
  table.sort(names)
  local c = v.c or 0
  if tol and abs(c) < tol then c = 0 end
  local s = ""
  if abs(c) >= 1e-14 then s = fmt(c, nil, dig) end
  for _, k in ipairs(names) do
    local a = v.s[k]
    local sc = abs(ENV[k] or 1); if sc < 1 then sc = 1 end
    if abs(a) > 1e-14 and not (tol and abs(a) * sc < tol) then
      local cs = (abs(abs(a) - 1) < 1e-12) and "" or fmt(abs(a), nil, dig)
      local term = cs .. k
      if s == "" then s = (a < 0 and "-" or "") .. term
      else s = s .. (a < 0 and " - " or " + ") .. term end
    end
  end
  if s == "" then s = "0" end
  return s
end

------------------------------------------------------------------
-- Serializacion (para guardar el modelo dentro del documento .tns)
------------------------------------------------------------------
local function ser(v)
  local t = type(v)
  if t == "number" then return string.format("%.17g", v)
  elseif t == "boolean" then return v and "T" or "F"
  elseif t == "table" then
    local p = {}
    for k, x in pairs(v) do
      local ks = (type(k) == "number") and ("#" .. string.format("%.17g", k)) or tostring(k)
      local xs = ser(x)
      if xs then p[#p + 1] = ks .. "=" .. xs end
    end
    return "{" .. table.concat(p, ",") .. "}"
  end
  return nil
end

local function deser(s)
  local pos = 1
  local function val()
    local c = s:sub(pos, pos)
    if c == "{" then
      pos = pos + 1
      local t = {}
      while true do
        c = s:sub(pos, pos)
        if c == "," then pos = pos + 1; c = s:sub(pos, pos) end
        if c == "}" then pos = pos + 1; return t end
        if c == "" then return t end
        local a, b = s:find("^[^=]+", pos)
        local key = s:sub(a, b)
        pos = b + 2
        if key:sub(1, 1) == "#" then key = tonumber(key:sub(2)) end
        t[key] = val()
      end
    elseif c == "T" then pos = pos + 1; return true
    elseif c == "F" then pos = pos + 1; return false
    else
      local a, b = s:find("^[^,}]+", pos)
      local n = tonumber(s:sub(a, b))
      pos = b + 1
      return n
    end
  end
  return val()
end

------------------------------------------------------------------
-- MOTOR DE CALCULO (metodo directo de rigidez, 3 GDL por nudo)
------------------------------------------------------------------
local function clamp(x, a, b) if x < a then return a elseif x > b then return b end return x end

local function geom(e)
  local a, b = M.nodes[e.i], M.nodes[e.j]
  local dx, dy = b.x - a.x, b.y - a.y
  local L = sqrt(dx * dx + dy * dy)
  if L == 0 then return 0, 1, 0 end
  return L, dx / L, dy / L
end

-- Contexto del elemento: geometria, rigideces y cargas en ejes locales
local function mkctx(k)
  local e = M.elems[k]
  local L, c, s = geom(e)
  local sec = M.secs[e.s]
  local EA = sec.E * sec.A
  if M.ax == 2 then EA = EA * 1e4 end
  local ctx = {L = L, c = c, s = s, EA = EA, EI = sec.E * sec.I, D = {}, P = {}, tol = 1e-9 * L}
  for _, ld in ipairs(M.el) do
    if ld.e == k then
      local v1, v2 = Lval(ld.v1), Lval(ld.v2)
      if ld.t == 3 then
        ctx.P[#ctx.P + 1] = {a = clamp(ld.a, 0, L), px = 0, py = 0, m = v1}
      else
        local d, lx, ly, f = ld.d, 0, 0, 1
        if d == 1 or d == 5 then lx, ly = s, c; if d == 5 then f = abs(c) end
        elseif d == 2 or d == 6 then lx, ly = c, -s; if d == 6 then f = abs(s) end
        elseif d == 3 then ly = 1
        else lx = 1 end
        if ld.t == 2 then
          ctx.P[#ctx.P + 1] = {a = clamp(ld.a, 0, L), px = v1 * lx, py = v1 * ly, m = 0}
        else
          local a, b = ld.a, ld.b
          local w1, w2 = v1, v2
          if b <= 0 then b = L end
          if b < a then a, b = b, a; w1, w2 = w2, w1 end
          a, b = clamp(a, 0, L), clamp(b, 0, L)
          if b - a > ctx.tol then
            ctx.D[#ctx.D + 1] = {a = a, b = b, pa = w1 * lx * f, pb = w2 * lx * f,
                                 qa = w1 * ly * f, qb = w2 * ly * f}
          end
        end
      end
    end
  end
  local t = {0, L}
  for _, d in ipairs(ctx.D) do t[#t + 1] = d.a; t[#t + 1] = d.b end
  for _, p in ipairs(ctx.P) do t[#t + 1] = p.a end
  table.sort(t)
  local bp = {}
  for _, x in ipairs(t) do
    if #bp == 0 or x - bp[#bp] > ctx.tol then bp[#bp + 1] = x end
  end
  if #bp < 2 then bp[2] = L end
  bp[#bp] = L
  ctx.bp = bp
  return ctx
end

-- Carga lineal total del tramo [xa, xb]: q = q0 + q1*t ; p = p0 + p1*t
local function segLoad(ctx, xa, xb)
  local q0, q1, p0, p1 = 0, 0, 0, 0
  local xm = 0.5 * (xa + xb)
  for _, d in ipairs(ctx.D) do
    if d.a <= xm and xm <= d.b then
      local sq = (d.qb - d.qa) / (d.b - d.a)
      local sp = (d.pb - d.pa) / (d.b - d.a)
      q1 = q1 + sq; q0 = q0 + d.qa + sq * (xa - d.a)
      p1 = p1 + sp; p0 = p0 + d.pa + sp * (xa - d.a)
    end
  end
  return q0, q1, p0, p1
end

-- Estado S = {N, V, M, theta, v, u}; integracion EXACTA en el tramo
local function adv(S, h, q0, q1, p0, p1, EA, EI)
  local N, V, Mm, t, v, u = S[1], S[2], S[3], S[4], S[5], S[6]
  local h2 = h * h; local h3 = h2 * h; local h4 = h3 * h; local h5 = h4 * h
  return {
    N - (p0 * h + p1 * h2 / 2),
    V + q0 * h + q1 * h2 / 2,
    Mm + V * h + q0 * h2 / 2 + q1 * h3 / 6,
    t + (Mm * h + V * h2 / 2 + q0 * h3 / 6 + q1 * h4 / 24) / EI,
    v + t * h + (Mm * h2 / 2 + V * h3 / 6 + q0 * h4 / 24 + q1 * h5 / 120) / EI,
    u + (N * h - p0 * h2 / 2 - p1 * h3 / 6) / EA}
end

local function jump(S, ctx, x)
  for _, p in ipairs(ctx.P) do
    if abs(p.a - x) <= ctx.tol then
      S[1] = S[1] - p.px; S[2] = S[2] + p.py; S[3] = S[3] - p.m
    end
  end
end

local function cpy(S) return {S[1], S[2], S[3], S[4], S[5], S[6]} end

-- Recorre el elemento desde i; cb(x, S, tramo) recibe muestras
local function walk(ctx, S0, cb)
  local S = cpy(S0)
  jump(S, ctx, 0)
  local bp = ctx.bp
  for k = 1, #bp - 1 do
    local xa, xb = bp[k], bp[k + 1]
    local q0, q1, p0, p1 = segLoad(ctx, xa, xb)
    if cb then
      cb(xa, S, k)
      local n = max(2, ceil(40 * (xb - xa) / ctx.L))
      for m = 1, n - 1 do
        local h = (xb - xa) * m / n
        cb(xa + h, adv(S, h, q0, q1, p0, p1, ctx.EA, ctx.EI), k)
      end
    end
    S = adv(S, xb - xa, q0, q1, p0, p1, ctx.EA, ctx.EI)
    if cb then cb(xb, S, k) end
    jump(S, ctx, xb)
  end
  return S
end

-- Estado a la izquierda y a la derecha del punto x
local function query(ctx, S0, x)
  x = clamp(x, 0, ctx.L)
  local S = cpy(S0)
  if x <= ctx.tol then local R = cpy(S); jump(R, ctx, 0); return S, R end
  jump(S, ctx, 0)
  local bp = ctx.bp
  for k = 1, #bp - 1 do
    local xa, xb = bp[k], bp[k + 1]
    local q0, q1, p0, p1 = segLoad(ctx, xa, xb)
    if x <= xb + ctx.tol or k == #bp - 1 then
      local Lf = adv(S, x - xa, q0, q1, p0, p1, ctx.EA, ctx.EI)
      local R = cpy(Lf); jump(R, ctx, x)
      return Lf, R
    end
    S = adv(S, xb - xa, q0, q1, p0, p1, ctx.EA, ctx.EI)
    jump(S, ctx, xb)
  end
  return S, S
end

-- Fuerzas de empotramiento perfecto (elemento biempotrado), locales
local function fef(ctx)
  local L, EA, EI = ctx.L, ctx.EA, ctx.EI
  local E = walk(ctx, {0, 0, 0, 0, 0, 0}, nil)
  local f1 = E[6] * EA / L
  local a11, a12, a21, a22 = L * L / (2 * EI), -L / EI, L ^ 3 / (6 * EI), -L * L / (2 * EI)
  local r1, r2 = -E[4], -E[5]
  local det = a11 * a22 - a12 * a21
  local f2 = (r1 * a22 - a12 * r2) / det
  local f3 = (a11 * r2 - a21 * r1) / det
  local NL = E[1] - f1
  local VL = E[2] + f2
  local ML = E[3] + f2 * L - f3
  return {f1, f2, f3, NL, -VL, ML}
end

local function kloc(EA, EI, L)
  local a = EA / L; local b = 12 * EI / L ^ 3; local c = 6 * EI / L ^ 2
  local d = 4 * EI / L; local e = 2 * EI / L
  return {
    { a, 0, 0, -a, 0, 0},
    { 0, b, c, 0, -b, c},
    { 0, c, d, 0, -c, e},
    {-a, 0, 0, a, 0, 0},
    { 0, -b, -c, 0, b, -c},
    { 0, c, e, 0, -c, d}}
end

-- Condensacion estatica de los giros liberados (rotulas)
local function condense(k, f0, R)
  if #R == 0 then return k, f0, nil end
  local inv
  if #R == 1 then
    inv = {{1 / k[R[1]][R[1]]}}
  else
    local a, b, c, d = k[R[1]][R[1]], k[R[1]][R[2]], k[R[2]][R[1]], k[R[2]][R[2]]
    local det = a * d - b * c
    inv = {{d / det, -b / det}, {-c / det, a / det}}
  end
  local ks, fs = {}, {}
  for i = 1, 6 do
    ks[i] = {}
    local g = {}
    for r = 1, #R do
      local sm = 0
      for q = 1, #R do sm = sm + k[i][R[q]] * inv[q][r] end
      g[r] = sm
    end
    for j = 1, 6 do
      local v = k[i][j]
      for r = 1, #R do v = v - g[r] * k[R[r]][j] end
      ks[i][j] = v
    end
    local v = f0[i]
    for r = 1, #R do v = v - g[r] * f0[R[r]] end
    fs[i] = v
  end
  for _, r in ipairs(R) do
    for j = 1, 6 do ks[r][j] = 0; ks[j][r] = 0 end
    fs[r] = 0
  end
  return ks, fs, inv
end

local function toLocal(c, s, g)
  return {c * g[1] + s * g[2], -s * g[1] + c * g[2], g[3],
          c * g[4] + s * g[5], -s * g[4] + c * g[5], g[6]}
end
local function toGlobal(c, s, l)
  return {c * l[1] - s * l[2], s * l[1] + c * l[2], l[3],
          c * l[4] - s * l[5], s * l[4] + c * l[5], l[6]}
end
local function kGlobal(k, c, s)
  local T = {{c, s, 0, 0, 0, 0}, {-s, c, 0, 0, 0, 0}, {0, 0, 1, 0, 0, 0},
             {0, 0, 0, c, s, 0}, {0, 0, 0, -s, c, 0}, {0, 0, 0, 0, 0, 1}}
  local kt, G = {}, {}
  for i = 1, 6 do
    kt[i] = {}
    for j = 1, 6 do
      local v = 0
      for m = 1, 6 do v = v + k[i][m] * T[m][j] end
      kt[i][j] = v
    end
  end
  for i = 1, 6 do
    G[i] = {}
    for j = 1, 6 do
      local v = 0
      for m = 1, 6 do v = v + T[m][i] * kt[m][j] end
      G[i][j] = v
    end
  end
  return G
end

-- Gauss (K simetrica definida positiva). Devuelve nil,k si es singular
local function gsolve(A, b, n)
  local d0 = {}
  for i = 1, n do d0[i] = abs(A[i][i]) end
  for k = 1, n do
    local p = A[k][k]
    if not (d0[k] > 0 and p > 1e-11 * d0[k]) then return nil, k end
    local Ak = A[k]
    for i = k + 1, n do
      local f = A[i][k] / p
      if f ~= 0 then
        local Ai = A[i]
        for j = k, n do Ai[j] = Ai[j] - f * Ak[j] end
        b[i] = b[i] - f * b[k]
      end
    end
  end
  local x = {}
  for i = n, 1, -1 do
    local s = b[i]; local Ai = A[i]
    for j = i + 1, n do s = s - Ai[j] * x[j] end
    x[i] = s / Ai[i]
  end
  return x
end

local function golden(fn, a, b)
  local gr = 0.6180339887498949
  local c = b - gr * (b - a); local d = a + gr * (b - a)
  local fc, fd = fn(c), fn(d)
  for _ = 1, 32 do
    if fc > fd then b = d; d = c; fd = fc; c = b - gr * (b - a); fc = fn(c)
    else a = c; c = d; fc = fd; d = a + gr * (b - a); fd = fn(d) end
  end
  local x = 0.5 * (a + b)
  return x, fn(x)
end

local function solve(light)
  local nn, ne = #M.nodes, #M.elems
  if nn < 2 or ne < 1 then return nil, "Defina al menos 2 nudos\ny 1 elemento." end
  for k, e in ipairs(M.elems) do
    if not M.nodes[e.i] or not M.nodes[e.j] or e.i == e.j then
      return nil, "Elemento " .. k .. ": nudos invalidos." end
    if not M.secs[e.s] then return nil, "Elemento " .. k .. ": seccion invalida." end
    if geom(e) < 1e-12 then return nil, "Elemento " .. k .. ": longitud cero." end
    local sc = M.secs[e.s]
    if not (sc.E > 0 and sc.A > 0 and sc.I > 0) then
      return nil, "Seccion " .. e.s .. ": E, A e I\ndeben ser mayores que 0." end
  end
  for _, l in ipairs(M.nl) do
    if not M.nodes[l.n] then return nil, "Carga en nudo inexistente (" .. tostring(l.n) .. ")." end
  end
  for _, l in ipairs(M.el) do
    if not M.elems[l.e] then return nil, "Carga en elemento inexistente (" .. tostring(l.e) .. ")." end
  end

  local nd3 = 3 * nn
  local K, F = {}, {}
  for i = 1, nd3 do
    K[i] = {}; F[i] = 0
    for j = 1, nd3 do K[i][j] = 0 end
  end
  for _, l in ipairs(M.nl) do
    local b = 3 * (l.n - 1)
    F[b + 1] = F[b + 1] + Lval(l.fx); F[b + 2] = F[b + 2] + Lval(l.fy); F[b + 3] = F[b + 3] + Lval(l.m)
  end
  local EL, conn = {}, {}
  for k = 1, nn do conn[k] = {n = 0, r = 0} end
  for k, e in ipairs(M.elems) do
    local ctx = mkctx(k)
    local kl = kloc(ctx.EA, ctx.EI, ctx.L)
    local f0 = fef(ctx)
    local R = {}
    if e.hi == 2 then R[#R + 1] = 3 end
    if e.hj == 2 then R[#R + 1] = 6 end
    local ks, fs, inv = condense(kl, f0, R)
    local KG = kGlobal(ks, ctx.c, ctx.s)
    local FG = toGlobal(ctx.c, ctx.s, fs)
    local map = {3 * e.i - 2, 3 * e.i - 1, 3 * e.i, 3 * e.j - 2, 3 * e.j - 1, 3 * e.j}
    for a = 1, 6 do
      F[map[a]] = F[map[a]] - FG[a]
      local Ka = K[map[a]]
      for b = 1, 6 do Ka[map[b]] = Ka[map[b]] + KG[a][b] end
    end
    EL[k] = {ctx = ctx, kl = kl, f0 = f0, R = R, inv = inv, map = map}
    conn[e.i].n = conn[e.i].n + 1; conn[e.j].n = conn[e.j].n + 1
    if e.hi == 2 then conn[e.i].r = conn[e.i].r + 1 end
    if e.hj == 2 then conn[e.j].r = conn[e.j].r + 1 end
  end

  local fixed, pres, dummy = {}, {}, {}
  local nr = 0
  for k, p in ipairs(M.nodes) do
    if conn[k].n == 0 then return nil, "El nudo " .. k .. " no esta\nconectado a ningun elemento." end
    local r = SUP[p.sup].r
    local b = 3 * (k - 1)
    local sett = {p.sx, p.sy, p.sr}
    local spr = {p.kx, p.ky, p.kr}
    for a = 1, 3 do
      if r[a] == 1 then
        fixed[b + a] = true; pres[b + a] = sett[a]; nr = nr + 1
      elseif spr[a] > 0 then
        K[b + a][b + a] = K[b + a][b + a] + spr[a]; nr = nr + 1
      end
    end
    if r[3] == 0 and spr[3] <= 0 and conn[k].r == conn[k].n then
      if abs(F[b + 3]) > 0 then
        return nil, "Momento aplicado en el nudo " .. k .. ",\npero todas las barras llegan\narticuladas: no hay rigidez." end
      dummy[b + 3] = true; fixed[b + 3] = true; pres[b + 3] = 0
    end
  end
  local crel = 0
  for k = 1, nn do
    if dummy[3 * k] then crel = crel + conn[k].r - 1 else crel = crel + conn[k].r end
  end
  local GI = 3 * ne + nr - 3 * nn - crel

  local free = {}
  for i = 1, nd3 do if not fixed[i] then free[#free + 1] = i end end
  local d = {}
  for i = 1, nd3 do d[i] = pres[i] or 0 end
  local nf = #free
  if nf > 0 then
    local A, bb = {}, {}
    for a = 1, nf do
      local i = free[a]
      local Ki = K[i]
      local s = F[i]
      for j = 1, nd3 do if fixed[j] and d[j] ~= 0 then s = s - Ki[j] * d[j] end end
      bb[a] = s
      local Aa = {}
      for c = 1, nf do Aa[c] = Ki[free[c]] end
      A[a] = Aa
    end
    local x, bad = gsolve(A, bb, nf)
    if not x then
      local dof = free[bad]
      local g = {"X", "Y", "giro"}
      return nil, "ESTRUCTURA INESTABLE\n(mecanismo). Revise apoyos y\nrotulas. GDL: nudo " ..
        ceil(dof / 3) .. " (" .. g[(dof - 1) % 3 + 1] .. ")\nGI calculado = " .. GI
    end
    for a = 1, nf do d[free[a]] = x[a] end
  end

  -- Reacciones
  local RX = {}
  for k, p in ipairs(M.nodes) do
    local r = SUP[p.sup].r
    local b = 3 * (k - 1)
    local spr = {p.kx, p.ky, p.kr}
    local rr, has = {0, 0, 0}, false
    for a = 1, 3 do
      local i = b + a
      if r[a] == 1 then
        local s = -F[i]
        local Ki = K[i]
        for j = 1, nd3 do s = s + Ki[j] * d[j] end
        rr[a] = s; has = true
      elseif spr[a] > 0 then
        rr[a] = -spr[a] * d[i]; has = true
      end
    end
    if has then RX[k] = rr end
  end

  -- Resultados por elemento
  local qmax = {0, 0, 0, 0, 0, 0}
  local gx = {}
  for q = 1, 6 do gx[q] = {mx = {v = -HUGE}, mn = {v = HUGE}} end
  local dmax = {v = 0, e = 1, x = 0, ux = 0, uy = 0}
  for k, e in ipairs(M.elems) do
    local X = EL[k]
    local ctx = X.ctx
    local dg = {}
    for a = 1, 6 do dg[a] = d[X.map[a]] end
    local dl = toLocal(ctx.c, ctx.s, dg)
    local R = X.R
    if #R > 0 then
      local rhs = {}
      for r = 1, #R do
        local s = X.f0[R[r]]
        for j = 1, 6 do
          local isr = false
          for q = 1, #R do if R[q] == j then isr = true end end
          if not isr then s = s + X.kl[R[r]][j] * dl[j] end
        end
        rhs[r] = s
      end
      for r = 1, #R do
        local s = 0
        for q = 1, #R do s = s - X.inv[r][q] * rhs[q] end
        dl[R[r]] = s
      end
    end
    local f = {}
    for i = 1, 6 do
      local s = X.f0[i]
      for j = 1, 6 do s = s + X.kl[i][j] * dl[j] end
      f[i] = s
    end
    for _, r in ipairs(R) do f[r] = 0 end
    X.dl = dl; X.f = f
    X.S0 = {-f[1], f[2], -f[3], dl[3], dl[2], dl[1]}
    if not light then
    -- muestras
    local smp = {}
    local c, s = ctx.c, ctx.s
    walk(ctx, X.S0, function(x, S, seg)
      local ux, uy = S[6] * c - S[5] * s, S[6] * s + S[5] * c
      smp[#smp + 1] = {x = x, S = cpy(S), seg = seg, ux = ux, uy = uy}
      local dt = sqrt(ux * ux + uy * uy)
      if dt > dmax.v then dmax = {v = dt, e = k, x = x, ux = ux, uy = uy} end
    end)
    X.smp = smp
    -- extremos (con refinamiento por seccion aurea)
    X.ext = {}
    for q = 1, 6 do
      local mx, mn = {v = -HUGE, x = 0, i = 1}, {v = HUGE, x = 0, i = 1}
      for i, p in ipairs(smp) do
        local v = p.S[q]
        if v > mx.v then mx = {v = v, x = p.x, i = i} end
        if v < mn.v then mn = {v = v, x = p.x, i = i} end
      end
      for _, pr in ipairs({{mx, 1}, {mn, -1}}) do
        local ee, sg = pr[1], pr[2]
        local i = ee.i
        local pa, pb = smp[i - 1], smp[i + 1]
        if pa and pb and pa.seg == smp[i].seg and pb.seg == smp[i].seg then
          local xr, fr = golden(function(xx) local Lf = query(ctx, X.S0, xx); return sg * Lf[q] end, pa.x, pb.x)
          if fr > sg * ee.v then ee.v = sg * fr; ee.x = xr end
        end
      end
      X.ext[q] = {mx = mx, mn = mn}
      qmax[q] = max(qmax[q], abs(mx.v), abs(mn.v))
      if mx.v > gx[q].mx.v then gx[q].mx = {v = mx.v, x = mx.x, e = k} end
      if mn.v < gx[q].mn.v then gx[q].mn = {v = mn.v, x = mn.x, e = k} end
    end
    end
  end

  local cls
  if GI == 0 then cls = "Estable - ISOSTATICA (GI = 0)"
  elseif GI > 0 then cls = "Estable - HIPERESTATICA grado " .. GI
  else cls = "Estable (GI = " .. GI .. ", revise)" end

  return {d = d, RX = RX, EL = EL, GI = GI, cls = cls, dummy = dummy,
          qmax = qmax, gx = gx, dmax = dmax, F = F}
end

------------------------------------------------------------------
-- ECUACIONES POR TRAMO (polinomios exactos en x desde el nudo i)
------------------------------------------------------------------
local function polyShift(ct, xa)
  local n = #ct
  local cx = {}
  for j = 1, n do cx[j] = 0 end
  for k = 1, n do
    local p = k - 1
    local binom = 1
    for j = 0, p do
      cx[j + 1] = cx[j + 1] + ct[k] * binom * (-xa) ^ (p - j)
      binom = binom * (p - j) / (j + 1)
    end
  end
  return cx
end

local function polyEval(c, x)
  local s = 0
  for j = #c, 1, -1 do s = s * x + c[j] end
  return s
end

-- Devuelve la lista de tramos de un elemento con sus polinomios en x
local function tramos(X)
  local ctx = X.ctx
  local EI = ctx.EI
  local S = cpy(X.S0)
  jump(S, ctx, 0)
  local out = {}
  for k = 1, #ctx.bp - 1 do
    local xa, xb = ctx.bp[k], ctx.bp[k + 1]
    local q0, q1, p0, p1 = segLoad(ctx, xa, xb)
    local N0, V0, M0, t0, v0 = S[1], S[2], S[3], S[4], S[5]
    out[#out + 1] = {
      xa = xa, xb = xb,
      q  = polyShift({q0, q1}, xa),
      p  = polyShift({p0, p1}, xa),
      N  = polyShift({N0, -p0, -p1 / 2}, xa),
      V  = polyShift({V0, q0, q1 / 2}, xa),
      M  = polyShift({M0, V0, q0 / 2, q1 / 6}, xa),
      EIt = polyShift({EI * t0, M0, V0 / 2, q0 / 6, q1 / 24}, xa),
      EIv = polyShift({EI * v0, EI * t0, M0 / 2, V0 / 6, q0 / 24, q1 / 120}, xa),
    }
    S = adv(S, xb - xa, q0, q1, p0, p1, ctx.EA, ctx.EI)
    jump(S, ctx, xb)
  end
  return out
end

local SUPX = {"", "x", "x²", "x³", "x^4", "x^5"}

-- tamano de una forma lineal (con los valores de prueba de las incognitas)
local function Lmag(v)
  if type(v) ~= "table" then return abs(v) end
  local m = abs(v.c or 0)
  for k, a in pairs(v.s or {}) do
    local sc = abs(ENV[k] or 1); if sc < 1 then sc = 1 end
    m = max(m, abs(a) * sc)
  end
  return m
end

-- Polinomio en x; los coeficientes pueden ser numeros o formas lineales
local function polyStr(c, L, ref)
  local mag = 0
  for j = 1, #c do mag = max(mag, Lmag(c[j]) * L ^ (j - 1)) end
  if mag < 1e-9 * (ref or 0) or mag == 0 then return "0" end
  local s = ""
  for j = 1, #c do
    local v = c[j]
    local tolj = 1e-9 * mag / L ^ (j - 1)
    if Lmag(v) > tolj then
      local comps = {}
      if type(v) ~= "table" then comps[1] = {"", v}
      else
        if abs(v.c or 0) > tolj then comps[#comps + 1] = {"", v.c} end
        local names = {}
        for k in pairs(v.s or {}) do names[#names + 1] = k end
        table.sort(names)
        for _, k in ipairs(names) do
          local sc = abs(ENV[k] or 1); if sc < 1 then sc = 1 end
          if abs(v.s[k]) * sc > tolj then comps[#comps + 1] = {k, v.s[k]} end
        end
      end
      if #comps == 1 then
        local nm, a0 = comps[1][1], comps[1][2]
        local neg, a = a0 < 0, abs(a0)
        local cs
        if (j > 1 or nm ~= "") and abs(a - 1) < 1e-12 then cs = "" else cs = fmt(a, nil, 5) end
        local term = cs .. nm .. SUPX[j]
        if s == "" then s = (neg and "-" or "") .. term
        else s = s .. (neg and " - " or " + ") .. term end
      elseif #comps > 1 then
        local body = Lstr(v, tolj, 5)
        if s == "" and j == 1 then s = body
        else
          body = "(" .. body .. ")" .. SUPX[j]
          if s == "" then s = body else s = s .. " + " .. body end
        end
      end
    end
  end
  if s == "" then return "0" end
  return s
end

------------------------------------------------------------------
-- INTERFAZ  (estilo v1.1, inspirado en la app de tuberias)
------------------------------------------------------------------
local stack = {}
local MSG = nil
local VIEW = {zoom = 1, px = 0, py = 0, lbl = 1, num = true}

local C = {
  bg = {244, 247, 251}, hd = {14, 40, 82}, ac = {0, 146, 214},
  tx = {28, 32, 44}, sub = {118, 128, 146}, sel = {214, 234, 250},
  ok = {0, 128, 84}, err = {196, 36, 36}, w = {255, 255, 255},
  ln = {208, 216, 228}, ft = {228, 234, 243}, alt = {234, 240, 248},
  lab = {170, 200, 235}, sec = {226, 238, 250},
}

local function inv() platform.window:invalidate() end
local function cur() return stack[#stack] end
local function push(s) stack[#stack + 1] = s; if s.onEnter then s:onEnter() end; inv() end
local function pop()
  if #stack > 1 then stack[#stack] = nil end
  local s = cur(); if s and s.onEnter then s:onEnter() end
  inv()
end
local function showMsg(text, onOK, confirm)
  MSG = {text = text, ok = onOK, confirm = confirm}
  inv()
end
local function dirty() RES = nil end

local function font(gc, sz, st) gc:setFont("sansserif", st or "r", sz) end
local function txt(gc, s, x, y) gc:drawString(s, x, y, "top") end
local function col(gc, r, g, b) gc:setColorRGB(r, g, b) end
local function cc(gc, c) gc:setColorRGB(c[1], c[2], c[3]) end
local function bx(gc, x, y, w, h, c) cc(gc, c); gc:fillRect(x, y, w, h) end
local function txtR(gc, s, x, y) txt(gc, s, x - gc:getStringWidth(s), y) end
local function txtC(gc, s, x, y) txt(gc, s, x - gc:getStringWidth(s) / 2, y) end
local function tw(gc, s) return gc:getStringWidth(s) end

-- Encabezado con icono de portico y derechos de autor
local function cabecera(gc, t)
  bx(gc, 0, 0, W, 24, C.hd)
  bx(gc, 0, 24, W, 2, C.ac)
  bx(gc, 5, 6, 20, 3, C.ac)       -- viga
  bx(gc, 7, 9, 3, 10, C.w)        -- columna izq.
  bx(gc, 20, 9, 3, 10, C.w)       -- columna der.
  bx(gc, 4, 19, 8, 2, C.ac)
  bx(gc, 17, 19, 8, 2, C.ac)
  font(gc, 7)
  local cr = "© J. Vargas"
  local cw = tw(gc, cr)
  cc(gc, C.lab); txt(gc, cr, W - cw - 4, 7)
  font(gc, 11, "b")
  local tt = t
  while #tt > 3 and tw(gc, tt) > W - cw - 40 do tt = tt:sub(1, #tt - 1) end
  cc(gc, C.w); txt(gc, tt, 31, 4)
end

local function pie(gc, s, c)
  bx(gc, 0, H - 19, W, 1, C.ln)
  bx(gc, 0, H - 18, W, 18, C.ft)
  font(gc, 9)
  cc(gc, c or C.sub); txt(gc, s, 6, H - 16)
end

local function barra(gc, top, n, N, y0, alto)
  if n <= N then return end
  bx(gc, W - 5, y0, 3, alto, C.ln)
  local h = max(10, floor(alto * N / n))
  local y = y0 + floor((alto - h) * (top - 1) / max(1, n - N))
  bx(gc, W - 5, y, 3, h, C.ac)
end

local function copyt(t) local r = {}; for k, v in pairs(t) do r[k] = v end; return r end

-- Incognitas presentes en las cargas del modelo (ordenadas)
local function modelSyms()
  local set, list = {}, {}
  local function scan(v)
    if type(v) == "table" then
      for k, a in pairs(v.s or {}) do
        if a ~= 0 and not set[k] then set[k] = true; list[#list + 1] = k end
      end
    end
  end
  for _, l in ipairs(M.nl) do scan(l.fx); scan(l.fy); scan(l.m) end
  for _, l in ipairs(M.el) do scan(l.v1); if l.t == 1 then scan(l.v2) end end
  table.sort(list)
  return list
end

local function ensure()
  if RES then return true end
  local names = modelSyms()
  if type(M.symv) ~= "table" then M.symv = {} end
  local test = {}
  for _, k in ipairs(names) do
    if type(M.symv[k]) ~= "number" then M.symv[k] = 1 end
    test[k] = M.symv[k]
  end
  ENV = test
  local ok, r, err = pcall(solve)
  if not ok then showMsg("Error interno:\n" .. tostring(r)); return false end
  if not r then showMsg(err); return false end
  if #names > 0 then
    -- superposicion: resultado = base (incognitas = 0) + suma(incognita * caso unitario)
    local sym = {names = names, unit = {}}
    local function run(env)
      ENV = env
      local ok2, r2, e2 = pcall(solve, true)
      ENV = test
      if not ok2 then error(tostring(r2), 0) end
      if not r2 then error(e2, 0) end
      return r2
    end
    local ok3, e3 = pcall(function()
      sym.base = run({})
      for _, k in ipairs(names) do sym.unit[k] = run({[k] = 1}) end
    end)
    ENV = test
    if not ok3 then showMsg(tostring(e3)); return false end
    r.sym = sym
  end
  RES = r
  return true
end

-- Valor de un resultado como forma lineal de las incognitas
local function SYMV(get)
  if not RES.sym then return get(RES) end
  local S = RES.sym
  local c = get(S.base)
  local f = {c = c, s = {}}
  for _, k in ipairs(S.names) do f.s[k] = get(S.unit[k]) - c end
  return f
end

local function symTxt()
  if not (RES and RES.sym) then return "" end
  local p = {}
  for _, k in ipairs(RES.sym.names) do p[#p + 1] = k .. "=" .. fmt(ENV[k] or 0, nil, 4) end
  return table.concat(p, ", ")
end

local function scrollTo(s, N, n)
  if s.sel < s.top then s.top = s.sel end
  if s.sel > s.top + N - 1 then s.top = s.sel - N + 1 end
  if s.top > max(1, n - N + 1) then s.top = max(1, n - N + 1) end
  if s.top < 1 then s.top = 1 end
end

------------------------------------------------------------------
-- Pantalla: menu (circulos numerados, encabezados de seccion)
------------------------------------------------------------------
local function Menu(title, items, foot)
  local s = {title = title, items = items, sel = 1, top = 1, foot = foot}
  for i, it in ipairs(items) do if not it.hd then s.sel = i; break end end
  function s:paint(gc)
    cabecera(gc, self.title)
    local RH = 22
    local N = max(1, floor((H - 30 - 20) / RH))
    local n = #self.items
    scrollTo(self, N, n)
    local num = 0
    for j = 1, self.top - 1 do if not self.items[j].hd then num = num + 1 end end
    for j = self.top, min(n, self.top + N - 1) do
      local it = self.items[j]
      local y = 30 + (j - self.top) * RH
      if it.hd then
        bx(gc, 4, y + 3, W - 12, RH - 6, C.sec)
        font(gc, 9, "b"); cc(gc, C.ac); txt(gc, it[1], 10, y + 4)
      else
        num = num + 1
        local act = (j == self.sel)
        if act then bx(gc, 4, y, W - 12, RH - 3, C.sel); bx(gc, 4, y, 3, RH - 3, C.ac) end
        cc(gc, act and C.ac or C.hd)
        gc:fillArc(12, y + 1, 18, 18, 0, 360)
        font(gc, 9, "b")
        local ns = tostring(num)
        cc(gc, C.w); txt(gc, ns, 21 - floor(tw(gc, ns) / 2), y + 2)
        font(gc, 10, act and "b" or "r")
        cc(gc, act and C.hd or C.tx); txt(gc, it[1], 38, y + 2)
      end
    end
    barra(gc, self.top, n, N, 30, N * RH - 3)
    pie(gc, self.foot or "flechas: mover   enter: elegir   esc: volver")
  end
  function s:arrow(k)
    local n = #self.items
    local d = (k == "up") and -1 or ((k == "down") and 1 or 0)
    if d == 0 then return end
    local i = self.sel
    for _ = 1, n do
      i = (i - 1 + d) % n + 1
      if not self.items[i].hd then break end
    end
    self.sel = i
  end
  function s:char(ch)
    local d = tonumber(ch)
    if not d then return end
    local num = 0
    for i, it in ipairs(self.items) do
      if not it.hd then
        num = num + 1
        if num == d then self.sel = i; if it[2] then it[2]() end; return end
      end
    end
  end
  function s:kEnter() local f = self.items[self.sel][2]; if f then f() end end
  return s
end

------------------------------------------------------------------
-- Pantalla: resultados (recuadro destacado + secciones)
--   filas: {"#", titulo} seccion | {"=", texto} ecuacion | {"~", nota}
--          {"!", aviso} | {etiqueta, valor}
------------------------------------------------------------------
local function wrapRows(gc, rows)
  local out = {}
  for _, r in ipairs(rows) do
    if r[1] == "=" or r[1] == "~" then
      font(gc, 9, r[1] == "=" and "r" or "r")
      local t = r[2]
      local maxw = W - 26
      if tw(gc, t) <= maxw then out[#out + 1] = r
      else
        local first, ind = true, "        "
        while #t > 0 do
          local cut = #t
          if tw(gc, t) > maxw then
            local best = nil
            local i = 1
            while true do
              local a = t:find(" [%+%-] ", i)
              if not a then break end
              if tw(gc, t:sub(1, a - 1)) <= maxw then best = a else break end
              i = a + 1
            end
            if not best then
              best = nil
              for j = #t, 1, -1 do
                if t:sub(j, j) == " " and tw(gc, t:sub(1, j - 1)) <= maxw then best = j; break end
              end
            end
            cut = (best or #t + 1) - 1
          end
          out[#out + 1] = {r[1], (first and "" or ind) .. t:sub(1, cut)}
          t = t:sub(cut + 1):gsub("^ +", "")
          if not first and #t > 0 then t = t end
          first = false
          if #t > 0 then t = t end
        end
      end
    else
      out[#out + 1] = r
    end
  end
  return out
end

local function Res(title, build, opts)
  opts = opts or {}
  local s = {title = title, top = 1, build = build, opts = opts}
  function s:onEnter()
    local ok, D = pcall(self.build, self)
    if not ok then D = {head = {"Error", tostring(D)}, rows = {}, err = true} end
    self.D = D
    self.wr = nil
  end
  function s:paint(gc)
    if not self.D then self:onEnter() end
    local D = self.D
    cabecera(gc, D.title or self.title)
    local y = 30
    if D.head then
      bx(gc, 6, y, W - 12, 36, D.err and C.err or C.hd)
      bx(gc, 6, y + 34, W - 12, 2, C.ac)
      font(gc, 9); cc(gc, C.lab); txt(gc, D.head[1], 14, y + 2)
      local hv = D.head[2]
      font(gc, 12, "b")
      if tw(gc, hv) > W - 30 then font(gc, 10, "b") end
      if tw(gc, hv) > W - 30 then font(gc, 9, "b") end
      cc(gc, C.w); txt(gc, hv, 14, y + 15)
      y = y + 42
    end
    if not self.wr or self.wrW ~= W then self.wr = wrapRows(gc, D.rows); self.wrW = W end
    local lin = self.wr
    local RH = 17
    local N = max(1, floor((H - 20 - y) / RH))
    local n = #lin
    self.N, self.n = N, n
    if self.top > max(1, n - N + 1) then self.top = max(1, n - N + 1) end
    for j = self.top, min(n, self.top + N - 1) do
      local x = lin[j]
      local yy = y + (j - self.top) * RH
      if x[1] == "#" then
        bx(gc, 6, yy + 1, W - 14, RH - 2, C.sec)
        font(gc, 9, "b"); cc(gc, C.ac); txt(gc, x[2], 12, yy + 2)
      elseif x[1] == "=" then
        font(gc, 9); cc(gc, C.tx); txt(gc, x[2], 14, yy + 2)
      elseif x[1] == "~" then
        font(gc, 9); cc(gc, C.sub); txt(gc, x[2], 14, yy + 2)
      elseif x[1] == "!" then
        font(gc, 9, "b"); cc(gc, C.err); txt(gc, "! " .. x[2], 12, yy + 2)
      else
        font(gc, 9); cc(gc, C.sub); txt(gc, x[1], 14, yy + 2)
        local lw = tw(gc, x[1])
        font(gc, 10, "b")
        local vx = 150
        local vw = tw(gc, x[2])
        if vx + vw > W - 8 then
          font(gc, 9, "b"); vw = tw(gc, x[2])
          vx = max(20 + lw, W - 8 - vw)
        end
        cc(gc, C.tx); txt(gc, x[2], vx, yy + 1)
      end
    end
    barra(gc, self.top, n, N, y, N * RH)
    pie(gc, D.foot or self.opts.foot or "flechas: desplazar   esc: volver")
  end
  function s:arrow(k)
    if k == "down" and self.n and self.top + self.N - 1 < self.n then self.top = self.top + 1
    elseif k == "up" and self.top > 1 then self.top = self.top - 1
    elseif (k == "left" or k == "right") and self.opts.lr then
      self.opts.lr(self, k == "right" and 1 or -1); self.top = 1; self:onEnter()
    end
  end
  function s:kEnter() if self.opts.enter then self.opts.enter(self) end end
  function s:tab() if self.opts.tab then self.opts.tab(self) end end
  function s:char(ch) if self.opts.char then self.opts.char(self, ch) end end
  return s
end

------------------------------------------------------------------
-- Pantalla: formulario (campos en recuadros + boton GUARDAR)
------------------------------------------------------------------
local function lab(f, r) if type(f.l) == "function" then return f.l(r) end return f.l end
local function unitOf(f, r) if f.u then return f.u(r) end return "" end

local function Form(title, fields, rec, onOK, btn)
  local s = {title = title, F = fields, r = copyt(rec), sel = 1, top = 1, fresh = true, tx = {}, btn = btn or "GUARDAR"}
  local function edStr(v) if type(v) == "table" then return Lstr(v, nil, 10) end return numStr(v) end
  for i, f in ipairs(fields) do if f.t ~= "c" then s.tx[i] = edStr(s.r[f.k]) end end
  function s:commit(i)
    local f = self.F[i]
    if not f or f.t == "c" then return nil end
    local v
    if f.sym then v = Lparse(self.tx[i]) else v = parseNum(self.tx[i]) end
    if v == nil then return "Valor invalido: " .. lab(f, self.r) end
    if f.t == "i" then
      local mx = f.mx()
      if v ~= floor(v) or v < 1 or v > mx then
        return lab(f, self.r) .. ": entero de 1 a " .. mx end
    end
    if f.pos and v <= 0 then return lab(f, self.r) .. ": debe ser > 0" end
    if f.nn and v < 0 then return lab(f, self.r) .. ": no puede ser negativo" end
    self.r[f.k] = v
    self.tx[i] = edStr(v)
    return nil
  end
  function s:move(dl)
    local e = self:commit(self.sel)
    if e then self.msg = e; return false end
    self.msg = nil
    local n = #self.F + 1
    self.sel = (self.sel - 1 + dl) % n + 1
    self.fresh = true
    return true
  end
  function s:save()
    for i = 1, #self.F do
      local e = self:commit(i)
      if e then self.sel = i; self.msg = e; self.fresh = true; return end
    end
    local err = onOK(self.r)
    if err == "__keep" then return end
    if err then self.msg = err:gsub("\n", " "); return end
    pop()
  end
  function s:arrow(k)
    local f = self.F[self.sel]
    if k == "up" then self:move(-1)
    elseif k == "down" then self:move(1)
    elseif f and f.t == "c" and (k == "left" or k == "right") then
      local n = #f.o
      local v = self.r[f.k] + (k == "right" and 1 or -1)
      if v < 1 then v = n elseif v > n then v = 1 end
      self.r[f.k] = v
    end
  end
  function s:tab() self:move(1) end
  function s:backtab() self:move(-1) end
  function s:char(ch)
    local f = self.F[self.sel]
    if not f then return end
    self.msg = nil
    if f.t == "c" then
      local n = tonumber(ch)
      if n and n >= 1 and n <= #f.o then self.r[f.k] = n end
      return
    end
    if self.fresh then self.tx[self.sel] = ""; self.fresh = false end
    self.tx[self.sel] = self.tx[self.sel] .. ch
  end
  function s:back()
    local f = self.F[self.sel]
    if not f or f.t == "c" then return end
    self.fresh = false
    local t = self.tx[self.sel]
    local n = #t
    while n > 0 do
      local b = t:byte(n)
      n = n - 1
      if b < 128 or b >= 192 then break end
    end
    self.tx[self.sel] = t:sub(1, n)
  end
  function s:clear()
    local f = self.F[self.sel]
    if f and f.t ~= "c" then self.tx[self.sel] = ""; self.fresh = false end
  end
  function s:kEnter()
    if self.sel > #self.F then self:save() else self:move(1) end
  end
  function s:paint(gc)
    cabecera(gc, self.title)
    local RH = 23
    local n = #self.F + 1
    local N = max(1, floor((H - 30 - 20) / RH))
    scrollTo(self, N, n)
    local bw = 124
    local bxx = W - bw - 10
    for j = self.top, min(n, self.top + N - 1) do
      local y = 30 + (j - self.top) * RH
      local act = (j == self.sel)
      if j == n then
        font(gc, 10, "b")
        local bwid = 150
        bx(gc, floor(W / 2) - bwid / 2, y + 1, bwid, RH - 4, act and C.ac or C.hd)
        cc(gc, C.w); txt(gc, self.btn, floor(W / 2) - floor(tw(gc, self.btn) / 2), y + 2)
      else
        local f = self.F[j]
        if act then bx(gc, 3, y, W - 10, RH - 2, C.sel); bx(gc, 3, y, 3, RH - 2, C.ac) end
        local u = unitOf(f, self.r)
        local lt = lab(f, self.r)
        if u ~= "" then lt = lt .. " [" .. u .. "]" end
        font(gc, 9, act and "b" or "r")
        if tw(gc, lt) > bxx - 12 then font(gc, 7, act and "b" or "r") end
        cc(gc, act and C.hd or C.tx); txt(gc, lt, 9, y + 3)
        bx(gc, bxx, y + 1, bw, RH - 4, act and C.ac or C.ln)
        bx(gc, bxx + 1, y + 2, bw - 2, RH - 6, C.w)
        font(gc, 10)
        y = y + 1
        if f.t == "c" then
          local op = f.o[self.r[f.k]] or "?"
          local maxw = bw - 28
          while #op > 1 and tw(gc, op) > maxw do op = op:sub(1, #op - 1) end
          cc(gc, C.ac); txt(gc, "<", bxx + 4, y + 2)
          cc(gc, C.tx); txt(gc, op, bxx + 14, y + 2)
          cc(gc, C.ac); txt(gc, ">", bxx + bw - 11, y + 2)
        else
          local st = self.tx[j]
          while #st > 1 and tw(gc, st) > bw - 16 do st = st:sub(2) end
          if act and self.fresh then
            bx(gc, bxx + 3, y + 4, tw(gc, st) + 4, RH - 10, C.sel)
          end
          cc(gc, C.tx); txt(gc, st, bxx + 5, y + 2)
          if act and not self.fresh then cc(gc, C.ac); txt(gc, "_", bxx + 5 + tw(gc, st), y + 2) end
        end
      end
    end
    barra(gc, self.top, n, N, 30, N * RH - 2)
    if self.msg then pie(gc, self.msg, C.err)
    else pie(gc, "enter: siguiente   del: borrar   esc: cancelar") end
  end
  return s
end

------------------------------------------------------------------
-- Tablas del modelo (nudos, secciones, elementos, cargas)
------------------------------------------------------------------
local KINDS = {}

KINDS.nodes = {
  title = "Nudos y apoyos",
  arr = function() return M.nodes end,
  row = function(i, r)
    local t = "N" .. i .. "   (" .. fmt(r.x) .. " , " .. fmt(r.y) .. ")"
    if r.sup > 1 then t = t .. "   " .. SUP[r.sup].s end
    if r.kx > 0 or r.ky > 0 or r.kr > 0 then t = t .. " +resorte" end
    if r.sx ~= 0 or r.sy ~= 0 or r.sr ~= 0 then t = t .. " +asent." end
    return t
  end,
  new = function()
    local l = M.nodes[#M.nodes]
    if l then return nd(l.x, l.y, 1) end
    return nd(0, 0, 1)
  end,
  fields = function() return {
    {k = "x", l = "Coordenada x", t = "n", u = uL},
    {k = "y", l = "Coordenada y", t = "n", u = uL},
    {k = "sup", l = "Apoyo", t = "c", o = SUPN},
    {k = "sx", l = "Asentam. Δx", t = "n", u = uL},
    {k = "sy", l = "Asentam. Δy", t = "n", u = uL},
    {k = "sr", l = "Giro impuesto θ", t = "n", u = uRad},
    {k = "kx", l = "Resorte kx", t = "n", u = uK, nn = true},
    {k = "ky", l = "Resorte ky", t = "n", u = uK, nn = true},
    {k = "kr", l = "Resorte kθ", t = "n", u = uKr, nn = true},
  } end,
  del = function(i)
    for k, e in ipairs(M.elems) do
      if e.i == i or e.j == i then return "El nudo " .. i .. " lo usa el\nelemento " .. k .. ". Borre primero\nel elemento." end
    end
    for k = #M.nl, 1, -1 do
      if M.nl[k].n == i then table.remove(M.nl, k) elseif M.nl[k].n > i then M.nl[k].n = M.nl[k].n - 1 end
    end
    for _, e in ipairs(M.elems) do
      if e.i > i then e.i = e.i - 1 end
      if e.j > i then e.j = e.j - 1 end
    end
    table.remove(M.nodes, i)
  end,
}

KINDS.secs = {
  title = "Secciones (E, A, I)",
  arr = function() return M.secs end,
  row = function(i, r) return "S" .. i .. "  E=" .. fmt(r.E, nil, 4) .. "  A=" .. fmt(r.A, nil, 4) .. "  I=" .. fmt(r.I, nil, 4) end,
  new = function() local l = M.secs[#M.secs]; return copyt(l) end,
  fields = function() return {
    {k = "E", l = "Modulo E", t = "n", u = uE, pos = true},
    {k = "A", l = "Area A", t = "n", u = uA, pos = true},
    {k = "I", l = "Inercia I", t = "n", u = uI, pos = true},
  } end,
  del = function(i)
    if #M.secs <= 1 then return "Debe existir al menos\nuna seccion." end
    for k, e in ipairs(M.elems) do
      if e.s == i then return "La seccion " .. i .. " la usa\nel elemento " .. k .. "." end
    end
    for _, e in ipairs(M.elems) do if e.s > i then e.s = e.s - 1 end end
    table.remove(M.secs, i)
  end,
}

KINDS.elems = {
  title = "Elementos",
  arr = function() return M.elems end,
  row = function(i, r)
    local t = "E" .. i .. "   N" .. r.i .. " → N" .. r.j .. "   S" .. r.s
    if M.nodes[r.i] and M.nodes[r.j] then t = t .. "   L=" .. fmt(geom(r), nil, 4) end
    if r.hi == 2 or r.hj == 2 then
      t = t .. "  rot:" .. (r.hi == 2 and "i" or "") .. (r.hj == 2 and "j" or "")
    end
    return t
  end,
  new = function()
    local n = #M.nodes
    return {i = max(1, n - 1), j = max(1, n), s = 1, hi = 1, hj = 1}
  end,
  fields = function() return {
    {k = "i", l = "Nudo inicial i", t = "i", mx = function() return #M.nodes end},
    {k = "j", l = "Nudo final j", t = "i", mx = function() return #M.nodes end},
    {k = "s", l = "Seccion", t = "i", mx = function() return #M.secs end},
    {k = "hi", l = "Rotula en i", t = "c", o = SINO},
    {k = "hj", l = "Rotula en j", t = "c", o = SINO},
  } end,
  check = function(r)
    if r.i == r.j then return "Los nudos i y j deben ser distintos" end
    local a, b = M.nodes[r.i], M.nodes[r.j]
    if a.x == b.x and a.y == b.y then return "Los nudos i y j tienen las mismas coordenadas" end
  end,
  del = function(i)
    for k = #M.el, 1, -1 do
      if M.el[k].e == i then table.remove(M.el, k) elseif M.el[k].e > i then M.el[k].e = M.el[k].e - 1 end
    end
    table.remove(M.elems, i)
  end,
}

KINDS.nl = {
  title = "Cargas en nudos",
  arr = function() return M.nl end,
  row = function(i, r)
    return "#" .. i .. "  N" .. r.n .. "   Fx=" .. Lstr(r.fx, nil, 4) .. "  Fy=" .. Lstr(r.fy, nil, 4) .. "  M=" .. Lstr(r.m, nil, 4)
  end,
  new = function() return {n = max(1, #M.nodes), fx = 0, fy = 0, m = 0} end,
  fields = function() return {
    {k = "n", l = "Nudo", t = "i", mx = function() return #M.nodes end},
    {k = "fx", l = "Fx (+ derecha)", t = "n", u = uF, sym = true},
    {k = "fy", l = "Fy (+ arriba)", t = "n", u = uF, sym = true},
    {k = "m", l = "M (+ antihorario)", t = "n", u = uM, sym = true},
  } end,
  del = function(i) table.remove(M.nl, i) end,
}

local function elLab1(r) if r.t == 1 then return "w1 (inicio)" elseif r.t == 2 then return "P" end return "M0 (+ antihor.)" end
local function elU1(r) if r.t == 1 then return uW() elseif r.t == 2 then return uF() end return uM() end
KINDS.el = {
  title = "Cargas en elementos",
  arr = function() return M.el end,
  row = function(i, r)
    local t = "#" .. i .. " E" .. r.e .. " "
    if r.t == 1 then
      t = t .. "w " .. Lstr(r.v1, nil, 4) .. ".." .. Lstr(r.v2, nil, 4) .. " " .. LDS[r.d] .. " [" .. fmt(r.a, nil, 4) .. "," .. (r.b > 0 and fmt(r.b, nil, 4) or "L") .. "]"
    elseif r.t == 2 then
      t = t .. "P=" .. Lstr(r.v1, nil, 4) .. " " .. LDS[r.d] .. " a=" .. fmt(r.a, nil, 4)
    else
      t = t .. "M=" .. Lstr(r.v1, nil, 4) .. " a=" .. fmt(r.a, nil, 4)
    end
    return t
  end,
  new = function() return {e = max(1, #M.elems), t = 1, d = 1, v1 = 0, v2 = 0, a = 0, b = 0} end,
  fields = function() return {
    {k = "e", l = "Elemento", t = "i", mx = function() return #M.elems end},
    {k = "t", l = "Tipo", t = "c", o = LT},
    {k = "d", l = function(r) return r.t == 3 and "Direccion (no aplica)" or "Direccion" end, t = "c", o = LD},
    {k = "v1", l = elLab1, t = "n", u = elU1, sym = true},
    {k = "v2", l = function(r) return r.t == 1 and "w2 (final)" or "(no aplica)" end, t = "n", u = function(r) return r.t == 1 and uW() or "" end, sym = true},
    {k = "a", l = function(r) return r.t == 1 and "a: inicio desde i" or "a: distancia desde i" end, t = "n", u = uL, nn = true},
    {k = "b", l = function(r) return r.t == 1 and "b: fin (0 = L)" or "(no aplica)" end, t = "n", u = uL, nn = true},
  } end,
  check = function(r)
    local e = M.elems[r.e]
    local L = geom(e)
    if r.a > L * (1 + 1e-9) then return "a es mayor que L = " .. fmt(L) end
    if r.t == 1 and r.b > L * (1 + 1e-9) then return "b es mayor que L = " .. fmt(L) end
    if r.t == 1 and r.b > 0 and abs(r.b - r.a) < 1e-12 then return "La distribuida necesita b distinto de a" end
  end,
  del = function(i) table.remove(M.el, i) end,
}

local function List(kind)
  local K = KINDS[kind]
  local s = {sel = 1, top = 1}
  function s:paint(gc)
    local arr = K.arr()
    cabecera(gc, K.title .. "  (" .. #arr .. ")")
    local RH = 20
    local N = max(1, floor((H - 30 - 20) / RH))
    if self.sel > #arr then self.sel = max(1, #arr) end
    scrollTo(self, N, #arr)
    if #arr == 0 then
      font(gc, 10); cc(gc, C.sub); txt(gc, "(vacío)   presione  +  para agregar", 14, 40)
    end
    for i = self.top, min(#arr, self.top + N - 1) do
      local y = 30 + (i - self.top) * RH
      local act = (i == self.sel)
      if act then bx(gc, 4, y, W - 12, RH - 2, C.sel); bx(gc, 4, y, 3, RH - 2, C.ac)
      elseif (i - self.top) % 2 == 1 then bx(gc, 4, y, W - 12, RH - 2, C.alt) end
      font(gc, 10, act and "b" or "r")
      local t = K.row(i, arr[i])
      if tw(gc, t) > W - 26 then font(gc, 9, act and "b" or "r") end
      cc(gc, act and C.hd or C.tx); txt(gc, t, 12, y + 2)
    end
    barra(gc, self.top, #arr, N, 30, N * RH - 2)
    pie(gc, "+: agregar   enter: editar   del: borrar   esc: volver")
  end
  function s:arrow(k)
    local n = #K.arr()
    if n == 0 then return end
    if k == "up" then self.sel = self.sel > 1 and self.sel - 1 or n
    elseif k == "down" then self.sel = self.sel < n and self.sel + 1 or 1 end
  end
  local function open(idx)
    local arr = K.arr()
    local rec = idx and arr[idx] or K.new()
    if kind == "elems" and #M.nodes < 2 then showMsg("Primero defina al menos\n2 nudos."); return end
    if (kind == "nl") and #M.nodes < 1 then showMsg("Primero defina nudos."); return end
    if (kind == "el") and #M.elems < 1 then showMsg("Primero defina elementos."); return end
    local ttl = idx and (K.title .. " #" .. idx) or ("Nuevo: " .. K.title)
    push(Form(ttl, K.fields(), rec, function(r)
      if K.check then local e = K.check(r); if e then return e end end
      if idx then arr[idx] = r else arr[#arr + 1] = r; s.sel = #arr end
      dirty()
    end))
  end
  function s:kEnter() if #K.arr() > 0 then open(self.sel) else open(nil) end end
  function s:char(ch) if ch == "+" then open(nil) end end
  local function del()
    local arr = K.arr()
    if #arr == 0 then return end
    local i = s.sel
    showMsg("¿Borrar el registro " .. i .. "?", function()
      local e = K.del(i)
      if e then showMsg(e) else dirty() end
    end, true)
  end
  s.back = del
  s.del = del
  return s
end

------------------------------------------------------------------
-- Unidades y opciones
------------------------------------------------------------------
local function convertModel(fu0, lu0, fu1, lu1)
  local f = FSI[fu0] / FSI[fu1]
  local l = LSI[lu0] / LSI[lu1]
  for _, p in ipairs(M.nodes) do
    p.x = p.x * l; p.y = p.y * l; p.sx = p.sx * l; p.sy = p.sy * l
    p.kx = p.kx * f / l; p.ky = p.ky * f / l; p.kr = p.kr * f * l
  end
  for _, s in ipairs(M.secs) do s.E = s.E * f / (l * l); s.A = s.A * l * l; s.I = s.I * l ^ 4 end
  for _, q in ipairs(M.nl) do q.fx = Lscale(q.fx, f); q.fy = Lscale(q.fy, f); q.m = Lscale(q.m, f * l) end
  for _, q in ipairs(M.el) do
    if q.t == 1 then q.v1 = Lscale(q.v1, f / l); q.v2 = Lscale(q.v2, f / l)
    elseif q.t == 2 then q.v1 = Lscale(q.v1, f)
    else q.v1 = Lscale(q.v1, f * l) end
    q.a = q.a * l; q.b = q.b * l
  end
end

local function UnitsForm()
  local rec = {fu = M.fu, lu = M.lu, cv = 2, ax = M.ax, ms = M.ms}
  return Form("Unidades y opciones", {
    {k = "fu", l = "Unidad de fuerza", t = "c", o = FU},
    {k = "lu", l = "Unidad de longitud", t = "c", o = LU},
    {k = "cv", l = "Convertir datos", t = "c", o = SINO},
    {k = "ax", l = "Deformacion axial", t = "c", o = {"Considerar", "Despreciar"}},
    {k = "ms", l = "Dibujo de M (+)", t = "c", o = {"Hacia +y' (viga)", "Lado traccion"}},
  }, rec, function(r)
    if r.cv == 2 and (r.fu ~= M.fu or r.lu ~= M.lu) then
      convertModel(M.fu, M.lu, r.fu, r.lu)
    end
    M.fu, M.lu, M.ax, M.ms = r.fu, r.lu, r.ax, r.ms
    dirty()
  end)
end

------------------------------------------------------------------
-- Dibujo del modelo
------------------------------------------------------------------
local function makeTx(top, bot, mar)
  local x0, x1, y0, y1 = HUGE, -HUGE, HUGE, -HUGE
  for _, p in ipairs(M.nodes) do
    x0 = min(x0, p.x); x1 = max(x1, p.x); y0 = min(y0, p.y); y1 = max(y1, p.y)
  end
  if #M.nodes == 0 then x0, x1, y0, y1 = 0, 1, 0, 1 end
  local aw, ah = W - 2 * mar, H - top - bot - 2 * mar
  local dx, dy = x1 - x0, y1 - y0
  local sc
  if dx < 1e-12 and dy < 1e-12 then sc = 1
  elseif dx < 1e-12 then sc = ah / dy
  elseif dy < 1e-12 then sc = aw / dx
  else sc = min(aw / dx, ah / dy) end
  sc = sc * VIEW.zoom
  local cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
  local ox, oy = W / 2 + VIEW.px, top + mar + ah / 2 + VIEW.py
  return function(x, y) return ox + (x - cx) * sc, oy - (y - cy) * sc end, sc
end

local function arrow(gc, x1, y1, x2, y2, hs)
  gc:drawLine(x1, y1, x2, y2)
  local dx, dy = x2 - x1, y2 - y1
  local l = sqrt(dx * dx + dy * dy)
  if l < 1e-9 then return end
  dx, dy = dx / l, dy / l
  hs = hs or 5
  local bxx, byy = x2 - dx * hs, y2 - dy * hs
  gc:fillPolygon({x2, y2, bxx - dy * hs * 0.45, byy + dx * hs * 0.45, bxx + dy * hs * 0.45, byy - dx * hs * 0.45, x2, y2})
end

local function marc(gc, x, y, r, ccw)
  gc:drawArc(x - r, y - r, 2 * r, 2 * r, 45, 270)
  local ang = ccw and math.rad(315) or math.rad(45)
  local ex, ey = x + r * math.cos(ang), y - r * math.sin(ang)
  local tx, ty
  if ccw then tx, ty = -math.sin(ang), -math.cos(ang) else tx, ty = math.sin(ang), math.cos(ang) end
  arrow(gc, ex - tx * 5, ey - ty * 5, ex + tx, ey + ty, 5)
end

local function hinge(gc, x, y)
  col(gc, 255, 255, 255); gc:fillArc(x - 3, y - 3, 6, 6, 0, 360)
  col(gc, 0, 0, 0); gc:drawArc(x - 3, y - 3, 6, 6, 0, 360)
end

local function nodeDir(k)
  local sx, sy = 0, 0
  for _, e in ipairs(M.elems) do
    local o
    if e.i == k then o = e.j elseif e.j == k then o = e.i end
    if o and M.nodes[o] then
      local a, b = M.nodes[k], M.nodes[o]
      local dx, dy = b.x - a.x, b.y - a.y
      local l = sqrt(dx * dx + dy * dy)
      if l > 0 then sx = sx + dx / l; sy = sy + dy / l end
    end
  end
  return sx, sy
end

local function ground(gc, bxx, byy, px, py, gx, gy, hw)
  gc:drawLine(bxx - px * hw, byy - py * hw, bxx + px * hw, byy + py * hw)
  local t = -hw + 2
  while t <= hw do
    local x, y = bxx + px * t, byy + py * t
    gc:drawLine(x, y, x + gx * 4 - px * 3, y + gy * 4 - py * 3)
    t = t + 4
  end
end

local function drawSupport(gc, k, X, Y)
  local p = M.nodes[k]
  local st = p.sup
  local sx, sy = nodeDir(k)
  col(gc, 0, 120, 0)
  if st > 1 then
    local gx, gy
    if st == 3 or st == 4 or st == 6 then gx, gy = 0, (sy < -0.5) and 1 or -1
    elseif st == 5 or st == 7 then gx, gy = (sx >= 0) and -1 or 1, 0
    else
      if abs(sy) > abs(sx) then gx, gy = 0, (sy > 0) and -1 or 1
      elseif abs(sx) > 1e-9 then gx, gy = (sx > 0) and -1 or 1, 0
      else gx, gy = 0, -1 end
    end
    local Gx, Gy = gx, -gy
    local Px, Py = -Gy, Gx
    if st == 2 then
      gc:setPen("medium", "smooth")
      gc:drawLine(X - Px * 8, Y - Py * 8, X + Px * 8, Y + Py * 8)
      gc:setPen("thin", "smooth")
      ground(gc, X, Y, Px, Py, Gx, Gy, 8)
    elseif st == 3 or st == 4 or st == 5 then
      local d = 9
      local bxx, byy = X + Gx * d, Y + Gy * d
      gc:drawPolyLine({X, Y, bxx + Px * 6, byy + Py * 6, bxx - Px * 6, byy - Py * 6, X, Y})
      if st == 3 then
        ground(gc, bxx, byy, Px, Py, Gx, Gy, 8)
      else
        gc:drawArc(bxx + Gx * 2 + Px * 3 - 2, byy + Gy * 2 + Py * 3 - 2, 4, 4, 0, 360)
        gc:drawArc(bxx + Gx * 2 - Px * 3 - 2, byy + Gy * 2 - Py * 3 - 2, 4, 4, 0, 360)
        ground(gc, bxx + Gx * 4, byy + Gy * 4, Px, Py, Gx, Gy, 8)
      end
    else
      gc:setPen("medium", "smooth")
      gc:drawLine(X - Px * 7, Y - Py * 7, X + Px * 7, Y + Py * 7)
      gc:setPen("thin", "smooth")
      gc:drawArc(X + Gx * 3 + Px * 4 - 2, Y + Gy * 3 + Py * 4 - 2, 4, 4, 0, 360)
      gc:drawArc(X + Gx * 3 - Px * 4 - 2, Y + Gy * 3 - Py * 4 - 2, 4, 4, 0, 360)
      ground(gc, X + Gx * 6, Y + Gy * 6, Px, Py, Gx, Gy, 8)
    end
  end
  if p.kx > 0 or p.ky > 0 or p.kr > 0 then
    font(gc, 7); col(gc, 0, 120, 0); txt(gc, "k", X - 10, Y - 12)
  end
end

local function drawStructure(gc, tx, light)
  gc:setPen("thin", "smooth")
  for _, e in ipairs(M.elems) do
    local a, b = M.nodes[e.i], M.nodes[e.j]
    if a and b then
      local x1, y1 = tx(a.x, a.y)
      local x2, y2 = tx(b.x, b.y)
      if light then col(gc, 160, 160, 160) else cc(gc, C.hd); gc:setPen("medium", "smooth") end
      gc:drawLine(x1, y1, x2, y2)
      gc:setPen("thin", "smooth")
      local dx, dy = x2 - x1, y2 - y1
      local l = sqrt(dx * dx + dy * dy)
      if l > 0 then
        dx, dy = dx / l, dy / l
        if e.hi == 2 then hinge(gc, x1 + dx * 5, y1 + dy * 5) end
        if e.hj == 2 then hinge(gc, x2 - dx * 5, y2 - dy * 5) end
      end
    end
  end
  for k, p in ipairs(M.nodes) do
    local X, Y = tx(p.x, p.y)
    drawSupport(gc, k, X, Y)
    col(gc, 0, 0, 0); gc:fillRect(X - 1, Y - 1, 3, 3)
  end
  if VIEW.num and not light then
    font(gc, 7)
    for k, p in ipairs(M.nodes) do
      local X, Y = tx(p.x, p.y)
      cc(gc, C.ac); txt(gc, tostring(k), X + 3, Y + 1)
    end
    for k, e in ipairs(M.elems) do
      local a, b = M.nodes[e.i], M.nodes[e.j]
      if a and b then
        local x1, y1 = tx(a.x, a.y); local x2, y2 = tx(b.x, b.y)
        local mx, my = (x1 + x2) / 2, (y1 + y2) / 2
        local s = "E" .. k
        local w = tw(gc, s)
        bx(gc, mx - w / 2 - 2, my - 5, w + 4, 10, C.hd)
        cc(gc, C.w); txt(gc, s, mx - w / 2, my - 6)
      end
    end
  end
end

local function drawLoads(gc, tx)
  -- las cargas con incognitas se dibujan con su valor de prueba
  local env = {}
  for _, k in ipairs(modelSyms()) do env[k] = (type(M.symv) == "table" and M.symv[k]) or 1 end
  local function Lval(v) return LvalE(v, env) end
  local wmax = 0
  for _, l in ipairs(M.el) do if l.t == 1 then wmax = max(wmax, abs(Lval(l.v1)), abs(Lval(l.v2))) end end
  if wmax == 0 then wmax = 1 end
  font(gc, 7)
  for _, l in ipairs(M.el) do
    local e = M.elems[l.e]
    if e and M.nodes[e.i] and M.nodes[e.j] then
      local A = M.nodes[e.i]
      local L, c, s = geom(e)
      local ux, uy
      if l.d == 1 or l.d == 5 then ux, uy = 0, 1
      elseif l.d == 2 or l.d == 6 then ux, uy = 1, 0
      elseif l.d == 3 then ux, uy = -s, c
      else ux, uy = c, s end
      local Ux, Uy = ux, -uy
      col(gc, 200, 60, 0)
      if l.t == 1 then
        local a, b = l.a, (l.b > 0) and l.b or L
        local w1, w2 = Lval(l.v1), Lval(l.v2)
        local s1, s2 = Lstr(l.v1, nil, 4), Lstr(l.v2, nil, 4)
        if b < a then a, b = b, a; w1, w2 = w2, w1; s1, s2 = s2, s1 end
        local pts = {}
        local n = 6
        for m = 0, n do
          local x = a + (b - a) * m / n
          local w = w1 + (w2 - w1) * m / n
          local X, Y = tx(A.x + x * c, A.y + x * s)
          local hgt = 4 + 12 * abs(w) / wmax
          local sg = (w >= 0) and 1 or -1
          local Tx, Ty = X - Ux * sg * hgt, Y - Uy * sg * hgt
          if abs(w) > 0 then arrow(gc, Tx, Ty, X, Y, 4) end
          pts[#pts + 1] = Tx; pts[#pts + 1] = Ty
        end
        gc:drawPolyLine(pts)
        local lbl = (s1 == s2) and s1 or (s1 .. "/" .. s2)
        txt(gc, lbl, pts[7] + 2, pts[8] - 10)
      elseif l.t == 2 then
        local X, Y = tx(A.x + l.a * c, A.y + l.a * s)
        local sg = (Lval(l.v1) >= 0) and 1 or -1
        arrow(gc, X - Ux * sg * 28, Y - Uy * sg * 28, X, Y, 5)
        txt(gc, Lstr(l.v1, nil, 4), X - Ux * sg * 28 + 3, Y - Uy * sg * 28 - 6)
      else
        local X, Y = tx(A.x + l.a * c, A.y + l.a * s)
        marc(gc, X, Y, 8, Lval(l.v1) >= 0)
        txt(gc, Lstr(l.v1, nil, 4), X + 8, Y - 16)
      end
    end
  end
  col(gc, 200, 0, 120)
  for _, l in ipairs(M.nl) do
    local p = M.nodes[l.n]
    if p then
      local X, Y = tx(p.x, p.y)
      local fx, fy, mm = Lval(l.fx), Lval(l.fy), Lval(l.m)
      if fx ~= 0 or type(l.fx) == "table" then
        local sg = fx >= 0 and 1 or -1
        arrow(gc, X - sg * 22, Y, X - sg * 2, Y, 5)
        local st = Lstr(l.fx, nil, 4)
        txt(gc, st, (sg > 0) and (X - 22 - tw(gc, st)) or (X + 22), Y - 11)
      end
      if fy ~= 0 or type(l.fy) == "table" then
        local sg = fy >= 0 and 1 or -1
        arrow(gc, X, Y + sg * 22, X, Y + sg * 2, 5)
        txt(gc, Lstr(l.fy, nil, 4), X + 3, Y + sg * 22 - (sg > 0 and 0 or 8))
      end
      if mm ~= 0 or type(l.m) == "table" then
        marc(gc, X, Y, 9, mm >= 0)
        txt(gc, Lstr(l.m, nil, 4), X + 9, Y - 18)
      end
    end
  end
end

------------------------------------------------------------------
-- Dibujo de resultados
------------------------------------------------------------------
local function drawReactions(gc, tx)
  local ref = 0
  for _, r in pairs(RES.RX) do ref = max(ref, abs(r[1]), abs(r[2]), abs(r[3])) end
  local tol = 1e-9 * ref
  font(gc, 7)
  local sx, sy = 0, 0
  for k, r in pairs(RES.RX) do
    local p = M.nodes[k]
    local X, Y = tx(p.x, p.y)
    col(gc, 0, 0, 200)
    if abs(r[1]) > tol then
      local sg = r[1] > 0 and 1 or -1
      arrow(gc, X - sg * 26, Y + 6, X - sg * 4, Y + 6, 5)
      local s = fmt(r[1], tol, 4)
      txt(gc, s, (sg > 0) and (X - 26 - tw(gc, s)) or (X + 28), Y + 1)
    end
    if abs(r[2]) > tol then
      local sg = r[2] > 0 and 1 or -1
      arrow(gc, X + 6, Y + sg * 28, X + 6, Y + sg * 4, 5)
      txt(gc, fmt(r[2], tol, 4), X + 9, Y + sg * 24 - 4)
    end
    if abs(r[3]) > tol then
      col(gc, 150, 0, 150)
      marc(gc, X, Y, 12, r[3] > 0)
      txt(gc, fmt(r[3], tol, 4), X - 30, Y - 22)
    end
    sx = sx + r[1]; sy = sy + r[2]
  end
  return sx, sy, tol
end

local function drawDiagram(gc, tx, q)
  local mxa = RES.qmax[q]
  local tol = 1e-9 * mxa
  if mxa < 1e-30 then mxa = 1 end
  local amp = 0.12 * min(W, H)
  local kk = amp / mxa
  local sgn = (q == 3 and M.ms == 2) and -1 or 1
  for ei, X in ipairs(RES.EL) do
    local e = M.elems[ei]
    local A = M.nodes[e.i]
    local c, s = X.ctx.c, X.ctx.s
    local nx, ny = -s * sgn, -c * sgn
    local pts = {}
    local function P(x, v)
      local bxx, byy = tx(A.x + x * c, A.y + x * s)
      return bxx, byy, bxx + nx * v * kk, byy + ny * v * kk
    end
    for _, p in ipairs(X.smp) do
      local v = p.S[q]
      if abs(v) < tol then v = 0 end
      local bxx, byy, ox, oy = P(p.x, v)
      if v > 0 then col(gc, 110, 170, 235) elseif v < 0 then col(gc, 240, 130, 130) end
      if v ~= 0 then gc:drawLine(bxx, byy, ox, oy) end
      pts[#pts + 1] = ox; pts[#pts + 1] = oy
    end
    cc(gc, C.hd)
    if #pts >= 4 then gc:drawPolyLine(pts) end
    if VIEW.lbl > 0 then
      font(gc, 7)
      local done = {}
      local function lab1(x, v, colr)
        if abs(v) < tol then v = 0 end
        for _, dd in ipairs(done) do if abs(dd - x) < 0.04 * X.ctx.L then return end end
        done[#done + 1] = x
        local _, _, ox, oy = P(x, v)
        col(gc, colr[1], colr[2], colr[3])
        gc:fillRect(ox - 1, oy - 1, 3, 3)
        local st = fmt(v, tol, 4)
        local ddir = (v >= 0) and 1 or -1
        local lx, ly = ox + nx * ddir * 3, oy + ny * ddir * 3
        local w = tw(gc, st)
        if nx * ddir < -0.3 then lx = lx - w end
        if abs(nx) <= 0.3 then lx = lx - w / 2 end
        if ny * ddir < -0.3 then ly = ly - 10 end
        txt(gc, st, lx, ly - 2)
      end
      local ex = X.ext[q]
      if ex.mx.v > tol then lab1(ex.mx.x, ex.mx.v, {0, 90, 170}) end
      if ex.mn.v < -tol then lab1(ex.mn.x, ex.mn.v, {170, 0, 0}) end
      if VIEW.lbl > 1 then
        local p1, p2 = X.smp[1], X.smp[#X.smp]
        lab1(p1.x, p1.S[q], {60, 60, 60})
        lab1(p2.x, p2.S[q], {60, 60, 60})
      end
    end
  end
end

local function drawDeformed(gc, tx, sc)
  local dm = RES.dmax.v
  drawStructure(gc, tx, true)
  if dm <= 0 then return 0 end
  local f = (0.12 * min(W, H) / sc) / dm
  cc(gc, C.ac)
  gc:setPen("medium", "smooth")
  for ei, X in ipairs(RES.EL) do
    local e = M.elems[ei]
    local A = M.nodes[e.i]
    local c, s = X.ctx.c, X.ctx.s
    local pts = {}
    for _, p in ipairs(X.smp) do
      local x, y = tx(A.x + p.x * c + f * p.ux, A.y + p.x * s + f * p.uy)
      pts[#pts + 1] = x; pts[#pts + 1] = y
    end
    if #pts >= 4 then gc:drawPolyLine(pts) end
  end
  gc:setPen("thin", "smooth")
  local X = RES.EL[RES.dmax.e]
  local e = M.elems[RES.dmax.e]
  local A = M.nodes[e.i]
  local x, y = tx(A.x + RES.dmax.x * X.ctx.c + f * RES.dmax.ux, A.y + RES.dmax.x * X.ctx.s + f * RES.dmax.uy)
  cc(gc, C.err); gc:fillRect(x - 2, y - 2, 5, 5)
  return f
end

local MODES = {"Modelo", "Reacciones", "Normal N", "Cortante V", "Momento M", "Rotacion θ", "Flecha δ (y')", "Deformada"}
local MQ = {nil, nil, 1, 2, 3, 4, 5, nil}

local ElemView, EqView -- declarados adelante

-- panel inferior de dos lineas (dato + teclas)
local function panel(gc, l1, l2)
  bx(gc, 0, H - 31, W, 1, C.ln)
  bx(gc, 0, H - 30, W, 30, C.ft)
  font(gc, 9, "b")
  if tw(gc, l1) > W - 8 then font(gc, 7, "b") end
  cc(gc, C.tx); txt(gc, l1, 5, H - 30)
  font(gc, 9)
  if tw(gc, l2) > W - 8 then font(gc, 7) end
  cc(gc, C.sub); txt(gc, l2, 5, H - 16)
end

local function Canvas(mode)
  local s = {mode = mode or 1}
  function s:paint(gc)
    if self.mode > 1 and not RES then
      if not ensure() then self.mode = 1 end
    end
    local mode = self.mode
    local mar = (mode == 1 or mode == 2) and 28 or 34
    local tx, sc = makeTx(27, 31, mar)
    local l1, l2 = "", ""
    if mode == 1 then
      drawStructure(gc, tx)
      drawLoads(gc, tx)
      l1 = "Unidades: " .. uF() .. ", " .. uL() .. "   Nudos: " .. #M.nodes .. "   Elementos: " .. #M.elems
      l2 = "tab: resultados   +/-: zoom   0: ajustar   n: números"
    elseif mode == 2 then
      drawStructure(gc, tx)
      local sx, sy, tol = drawReactions(gc, tx)
      l1 = RES.cls
      l2 = "ΣRx = " .. fmt(sx, tol) .. "   ΣRy = " .. fmt(sy, tol) .. "   [" .. uF() .. ", " .. uM() .. "]"
    elseif MQ[mode] then
      local q = MQ[mode]
      drawStructure(gc, tx, true)
      drawDiagram(gc, tx, q)
      local g = RES.gx[q]
      local tol = 1e-9 * RES.qmax[q]
      l1 = "máx " .. fmt(g.mx.v, tol) .. " (E" .. g.mx.e .. ", x=" .. fmt(g.mx.x, nil, 4) .. ")   mín " ..
           fmt(g.mn.v, tol) .. " (E" .. g.mn.e .. ", x=" .. fmt(g.mn.x, nil, 4) .. ")  [" .. QU[q]() .. "]"
      l2 = "tab: diagrama   enter: por elemento   e: ecuaciones   v: etiq."
      if RES.sym then l2 = "Prueba: " .. symTxt() .. "   enter: elemento   e: ecuaciones" end
    else
      local f = drawDeformed(gc, tx, sc)
      local dm = RES.dmax
      l1 = "|Δ|máx = " .. fmt(dm.v) .. " " .. uL() .. " en E" .. dm.e .. ", x=" .. fmt(dm.x, nil, 4) ..
           "   Δx=" .. fmt(dm.ux, 1e-9 * dm.v, 4) .. "  Δy=" .. fmt(dm.uy, 1e-9 * dm.v, 4)
      l2 = "Escala de dibujo x" .. fmt(f, nil, 3) .. "   tab: diagrama   esc: volver"
    end
    cabecera(gc, MODES[mode])
    panel(gc, l1, l2)
  end
  function s:tab()
    local n = self.mode % #MODES + 1
    if n > 1 and not ensure() then return end
    self.mode = n
  end
  function s:backtab()
    local n = self.mode - 1
    if n < 1 then n = #MODES end
    if n > 1 and not ensure() then return end
    self.mode = n
  end
  function s:arrow(k)
    local st = 20
    if k == "left" then VIEW.px = VIEW.px + st elseif k == "right" then VIEW.px = VIEW.px - st
    elseif k == "up" then VIEW.py = VIEW.py + st elseif k == "down" then VIEW.py = VIEW.py - st end
  end
  function s:char(ch)
    if ch == "+" or ch == "*" then VIEW.zoom = VIEW.zoom * 1.25
    elseif ch == "-" or ch == "−" or ch == "/" then VIEW.zoom = VIEW.zoom / 1.25
    elseif ch == "0" then VIEW.zoom, VIEW.px, VIEW.py = 1, 0, 0
    elseif ch == "v" or ch == "V" then VIEW.lbl = (VIEW.lbl + 1) % 3
    elseif ch == "n" or ch == "N" then VIEW.num = not VIEW.num
    elseif (ch == "e" or ch == "E") and #M.elems > 0 and ensure() then push(EqView(1))
    end
  end
  function s:kEnter()
    local q = MQ[self.mode] or 3
    if #M.elems > 0 and ensure() then push(ElemView(1, q, 0)) end
  end
  return s
end

------------------------------------------------------------------
-- Diagrama por elemento + punto de interes
------------------------------------------------------------------
ElemView = function(k, q, x)
  local s = {k = k, q = q or 3, x = x or 0}
  function s:paint(gc)
    if not RES and not ensure() then pop(); return end
    if not RES.EL[self.k] then self.k = 1 end
    local X = RES.EL[self.k]
    local ctx = X.ctx
    local L = ctx.L
    local e = M.elems[self.k]
    local q = self.q
    cabecera(gc, "E" .. self.k .. " (N" .. e.i .. "→N" .. e.j .. ")  " .. QL[q])
    local sgn = (q == 3 and M.ms == 2) and -1 or 1
    local px0, px1, py0, py1 = 34, W - 8, 42, H - 78
    local ex = X.ext[q]
    local tol = 1e-9 * RES.qmax[q]
    local vmx, vmn = ex.mx.v * sgn, ex.mn.v * sgn
    if sgn < 0 then vmx, vmn = vmn, vmx end
    local hi, lo = max(vmx, 0), min(vmn, 0)
    if hi - lo < 1e-30 then hi, lo = 1, -1 end
    local pad = 0.12 * (hi - lo)
    hi = hi + pad; lo = lo - pad
    local function PX(xx) return px0 + (px1 - px0) * xx / L end
    local function PY(v) return py1 - (py1 - py0) * (v - lo) / (hi - lo) end
    bx(gc, px0, py0, px1 - px0, py1 - py0, C.w)
    cc(gc, C.ln); gc:drawRect(px0, py0, px1 - px0, py1 - py0)
    local pts = {}
    local y0 = PY(0)
    for _, p in ipairs(X.smp) do
      local v = p.S[q]
      if abs(v) < tol then v = 0 end
      v = v * sgn
      local xx, yy = PX(p.x), PY(v)
      if v > 0 then col(gc, 150, 200, 240) elseif v < 0 then col(gc, 245, 165, 165) end
      if v ~= 0 then gc:drawLine(xx, y0, xx, yy) end
      pts[#pts + 1] = xx; pts[#pts + 1] = yy
    end
    cc(gc, C.sub); gc:drawLine(px0, y0, px1, y0)
    cc(gc, C.hd); gc:setPen("medium", "smooth")
    if #pts >= 4 then gc:drawPolyLine(pts) end
    gc:setPen("thin", "smooth")
    font(gc, 7)
    local smx = "máx " .. fmt(ex.mx.v, tol) .. " @x=" .. fmt(ex.mx.x, nil, 4)
    local smn = "mín " .. fmt(ex.mn.v, tol) .. " @x=" .. fmt(ex.mn.x, nil, 4)
    cc(gc, C.ac); txt(gc, smx, 4, 29)
    cc(gc, C.err); txtR(gc, smn, W - 4, 29)
    for _, m in ipairs({ex.mx, ex.mn}) do
      local v = m.v; if abs(v) < tol then v = 0 end
      gc:fillRect(PX(m.x) - 2, PY(v * sgn) - 2, 5, 5)
    end
    cc(gc, C.sub)
    txtR(gc, fmt(hi - pad, nil, 3), px0 - 2, PY(hi - pad) - 5)
    if lo + pad < 0 then txtR(gc, fmt(lo + pad, nil, 3), px0 - 2, PY(lo + pad) - 5) end
    txtR(gc, "0", px0 - 2, y0 - 5)
    txt(gc, "0", px0 - 2, py1 + 1); txtR(gc, fmt(L, nil, 4), px1, py1 + 1)
    local cxp = PX(self.x)
    cc(gc, C.ok); gc:drawLine(cxp, py0, cxp, py1)
    local Lf, Rt = query(ctx, X.S0, self.x)
    local symb = self.symb and RES.sym
    local kk, xx = self.k, self.x
    local function at(R, side)
      local XX = R.EL[kk]
      local a, b = query(XX.ctx, XX.S0, xx)
      if side == 2 then return b end
      return a
    end
    local function vs(qq)
      local t = 1e-9 * RES.qmax[qq]
      local a, b = Lf[qq], Rt[qq]
      if symb then
        local fa = Lstr(SYMV(function(R) return at(R, 1)[qq] end), t)
        if abs(a - b) > max(t, 1e-14) then
          return fa .. " / " .. Lstr(SYMV(function(R) return at(R, 2)[qq] end), t)
        end
        return fa
      end
      if abs(a - b) > max(t, 1e-14) then return fmt(a, t) .. " / " .. fmt(b, t) end
      return fmt(a, t)
    end
    local c, sn = ctx.c, ctx.s
    local ux, uy = Lf[6] * c - Lf[5] * sn, Lf[6] * sn + Lf[5] * c
    local yb = H - 66
    bx(gc, 4, yb, W - 8, 46, C.hd)
    bx(gc, 4, yb + 44, W - 8, 2, C.ac)
    font(gc, 9, "b"); cc(gc, C.w)
    txt(gc, "x = " .. fmt(self.x, nil, 6) .. " " .. uL() .. "   (L = " .. fmt(L) .. ")", 9, yb + 1)
    font(gc, 7); cc(gc, C.lab)
    txt(gc, "N = " .. vs(1) .. " " .. uF() .. "    V = " .. vs(2) .. " " .. uF() .. "    M = " .. vs(3) .. " " .. uM(), 9, yb + 14)
    txt(gc, "θ = " .. vs(4) .. " rad    δ(y') = " .. vs(5) .. "    u(x') = " .. vs(6) .. " " .. uL(), 9, yb + 24)
    local dt = 1e-9 * max(RES.dmax.v, 1e-30)
    local sx, sy = fmt(ux, dt), fmt(uy, dt)
    if symb then
      sx = Lstr(SYMV(function(R) local S = at(R, 1); return S[6] * c - S[5] * sn end), dt)
      sy = Lstr(SYMV(function(R) local S = at(R, 1); return S[6] * sn + S[5] * c end), dt)
    end
    txt(gc, "Global:  Δx = " .. sx .. "   Δy = " .. sy .. " " .. uL(), 9, yb + 34)
    if RES.sym then
      pie(gc, symb and ("s: ver números (" .. symTxt() .. ")") or "izq/der: x  arr/ab: elem.  e: ecuac.  s: símbolos")
    else
      pie(gc, "izq/der: x  arr/ab: elem.  tab: diag.  e: ecuac.")
    end
  end
  function s:arrow(kk)
    local L = RES.EL[self.k].ctx.L
    if kk == "left" then self.x = max(0, self.x - L / 40)
    elseif kk == "right" then self.x = min(L, self.x + L / 40)
    elseif kk == "up" or kk == "down" then
      local r = self.x / L
      local n = #RES.EL
      if kk == "up" then self.k = self.k % n + 1 else self.k = (self.k - 2) % n + 1 end
      self.x = r * RES.EL[self.k].ctx.L
    end
  end
  function s:tab() self.q = self.q % 6 + 1 end
  function s:backtab() self.q = (self.q - 2) % 6 + 1 end
  function s:char(ch)
    if ch == "+" or ch == "*" then self:arrow("right") elseif ch == "-" then self:arrow("left")
    elseif ch == "e" or ch == "E" then push(EqView(self.k))
    elseif (ch == "s" or ch == "S") and RES.sym then self.symb = not self.symb end
  end
  function s:kEnter()
    local me = self
    push(Form("Punto de interés", {
      {k = "e", l = "Elemento", t = "i", mx = function() return #M.elems end},
      {k = "x", l = "x desde el nudo i", t = "n", u = uL, nn = true},
    }, {e = self.k, x = self.x}, function(r)
      local L = RES.EL[r.e].ctx.L
      if r.x > L * (1 + 1e-9) then return "x supera L = " .. fmt(L) end
      me.k = r.e; me.x = min(r.x, L)
    end, "VER PUNTO"))
  end
  return s
end

------------------------------------------------------------------
-- Ecuaciones de cada elemento por tramos
------------------------------------------------------------------
-- tramos con coeficientes en funcion de las incognitas
local TKEYS = {"q", "p", "N", "V", "M", "EIt", "EIv"}
local function tramosL(k)
  if not RES.sym then return tramos(RES.EL[k]) end
  local S = RES.sym
  local tb = tramos(S.base.EL[k])
  local tu = {}
  for _, nm in ipairs(S.names) do tu[nm] = tramos(S.unit[nm].EL[k]) end
  for i, t in ipairs(tb) do
    for _, key in ipairs(TKEYS) do
      local arr, out = t[key], {}
      for j = 1, #arr do
        local f = {c = arr[j], s = {}}
        for _, nm in ipairs(S.names) do f.s[nm] = tu[nm][i][key][j] - arr[j] end
        out[j] = f
      end
      t[key] = out
    end
  end
  return tb
end

local function eqRows(k)
  local X = RES.EL[k]
  local e = M.elems[k]
  local ctx = X.ctx
  local L = ctx.L
  local rows = {}
  local tr = tramosL(k)
  local qm = RES.qmax
  local EI = ctx.EI
  rows[#rows + 1] = {"~", "x desde N" .. e.i .. " hacia N" .. e.j .. " [" .. uL() .. "];  F en " .. uF()}
  rows[#rows + 1] = {"EI", fmt(EI) .. " " .. uF() .. "·" .. uL() .. "²"}
  for i, t in ipairs(tr) do
    rows[#rows + 1] = {"#", "TRAMO " .. i .. ":  " .. fmt(t.xa, nil, 5) .. " ≤ x ≤ " .. fmt(t.xb, nil, 5) .. " " .. uL()}
    local hasq = Lmag(t.q[1]) + Lmag(t.q[2]) * L > 0
    local hasp = Lmag(t.p[1]) + Lmag(t.p[2]) * L > 0
    if hasq then rows[#rows + 1] = {"=", "q(x) = " .. polyStr(t.q, L)} end
    if hasp then rows[#rows + 1] = {"=", "p(x) = " .. polyStr(t.p, L)} end
    rows[#rows + 1] = {"=", "N(x) = " .. polyStr(t.N, L, qm[1])}
    rows[#rows + 1] = {"=", "V(x) = " .. polyStr(t.V, L, qm[2])}
    rows[#rows + 1] = {"=", "M(x) = " .. polyStr(t.M, L, qm[3])}
    rows[#rows + 1] = {"=", "EIθ(x) = " .. polyStr(t.EIt, L, qm[4] * EI)}
    rows[#rows + 1] = {"=", "EIδ(x) = " .. polyStr(t.EIv, L, qm[5] * EI)}
    if i < #tr then
      for ip, p in ipairs(ctx.P) do
        if abs(p.a - t.xb) <= ctx.tol then
          local parts = {}
          for _, it in ipairs({{"py", "Py'", "V"}, {"px", "Px'", "N"}, {"m", "M0", "M"}}) do
            local f = SYMV(function(R) return R.EL[k].ctx.P[ip][it[1]] end)
            if Lmag(f) > 0 then parts[#parts + 1] = it[2] .. "=" .. Lstr(f, nil, 4) .. " (salta " .. it[3] .. ")" end
          end
          if #parts > 0 then rows[#rows + 1] = {"~", "En x=" .. fmt(t.xb, nil, 5) .. ": " .. table.concat(parts, ", ")} end
        end
      end
    end
  end
  rows[#rows + 1] = {"#", "NOTAS"}
  rows[#rows + 1] = {"~", "θ = EIθ/EI [rad];  δ = EIδ/EI [" .. uL() .. "]"}
  rows[#rows + 1] = {"~", "dV/dx = q,  dM/dx = V,  EIθ' = M,  δ' = θ"}
  rows[#rows + 1] = {"~", "Signos: N+ tracción; V, M, θ, δ en ejes x', y'"}
  return rows
end

EqView = function(k)
  local view
  view = Res("Ecuaciones", function(self)
    if not RES and not ensure() then error("Sin solución") end
    local n = #RES.EL
    if self.k > n then self.k = 1 end
    local e = M.elems[self.k]
    return {title = "Ecuaciones  E" .. self.k .. " (" .. self.k .. "/" .. n .. ")",
            head = {"Elemento E" .. self.k .. ":  N" .. e.i .. " → N" .. e.j,
                    "L = " .. fmt(RES.EL[self.k].ctx.L) .. " " .. uL() .. "   (" .. #tramos(RES.EL[self.k]) .. (#tramos(RES.EL[self.k]) == 1 and " tramo)" or " tramos)")},
            rows = eqRows(self.k),
            foot = "arr/ab: desplazar  izq/der: elemento  enter: gráfico"}
  end, {
    lr = function(self, d) local n = #RES.EL; self.k = (self.k - 1 + d) % n + 1 end,
    enter = function(self) push(ElemView(self.k, 3, 0)) end,
  })
  view.k = k or 1
  return view
end

------------------------------------------------------------------
-- Tablas de resultados
------------------------------------------------------------------
local BUILD = {}

local function finalize(D)
  local refs = {}
  for _, r in ipairs(D.rows) do
    for j = 2, #r do if type(r[j]) == "number" then refs[j] = max(refs[j] or 0, abs(r[j])) end end
  end
  for _, r in ipairs(D.rows) do
    for j = 2, #r do if type(r[j]) == "number" then r[j] = fmt(r[j], 1e-9 * (refs[j] or 0)) end end
  end
  return D
end

-- celda: numero (se formatea despues) o texto en funcion de las incognitas
local function cell(get, tol)
  if RES.sym then return Lstr(SYMV(get), tol) end
  return get(RES)
end

BUILD.reac = function()
  local D = {title = "Reacciones", info = RES.cls,
             head = {"Nudo", "Rx [" .. uF() .. "]", "Ry [" .. uF() .. "]", "M [" .. uM() .. "]"}, rows = {}}
  local ref = 0
  for _, r in pairs(RES.RX) do ref = max(ref, abs(r[1]), abs(r[2]), abs(r[3])) end
  local tol = 1e-9 * ref
  for k = 1, #M.nodes do
    if RES.RX[k] then
      local row = {"N" .. k .. " " .. SUP[M.nodes[k].sup].s}
      for a = 1, 3 do row[a + 1] = cell(function(R) return R.RX[k][a] end, tol) end
      D.rows[#D.rows + 1] = row
    end
  end
  finalize(D)
  local function sum(a) return function(R) local s = 0; for _, r in pairs(R.RX) do s = s + r[a] end; return s end end
  local sx, sy = cell(sum(1), tol), cell(sum(2), tol)
  if type(sx) == "number" then sx, sy = fmt(sx, tol), fmt(sy, tol) end
  D.rows[#D.rows + 1] = {"Σ", sx, sy, ""}
  D.last = true
  if RES.sym then D.info = "En función de: " .. table.concat(RES.sym.names, ", ") end
  return D
end

BUILD.disp = function()
  local D = {title = "Desplazamientos", info = "Globales: +X der., +Y arriba, θ+ antihorario",
             head = {"Nudo", "Δx [" .. uL() .. "]", "Δy [" .. uL() .. "]", "θ [rad]"}, rows = {}}
  local ref = 0
  for i = 1, #RES.d do ref = max(ref, abs(RES.d[i])) end
  local tol = 1e-9 * ref
  for k = 1, #M.nodes do
    local b = 3 * (k - 1)
    local function g(i) return cell(function(R) return R.d[b + i] end, tol) end
    D.rows[#D.rows + 1] = {"N" .. k, g(1), g(2), RES.dummy[b + 3] and "(rótula)" or g(3)}
  end
  return finalize(D)
end

BUILD.ends = function()
  local D = {title = "Fuerzas en extremos", info = "N+ tracción; V, M según eje local x' (i→j)",
             head = {"Elem./ext.", "N [" .. uF() .. "]", "V [" .. uF() .. "]", "M [" .. uM() .. "]"}, rows = {}}
  local ref = {0, 0, 0}
  for _, X in ipairs(RES.EL) do
    for i = 1, 3 do ref[i] = max(ref[i], abs(X.f[i]), abs(X.f[i + 3])) end
  end
  for k, X in ipairs(RES.EL) do
    local e = M.elems[k]
    local function g(i, sg, r) return cell(function(R) return sg * R.EL[k].f[i] end, 1e-9 * ref[r]) end
    D.rows[#D.rows + 1] = {"E" .. k .. " i (N" .. e.i .. ")", g(1, -1, 1), g(2, 1, 2), g(3, -1, 3)}
    D.rows[#D.rows + 1] = {"     j (N" .. e.j .. ")", g(4, 1, 1), g(5, -1, 2), g(6, 1, 3)}
  end
  return finalize(D)
end

BUILD.max = function()
  local D = {title = "Máximos y mínimos", info = RES.cls,
             head = {"Magnitud", "Valor", "Elem.", "x [" .. uL() .. "]"}, rows = {}}
  for q = 1, 5 do
    local g = RES.gx[q]
    local tol = 1e-9 * RES.qmax[q]
    D.rows[#D.rows + 1] = {QN[q] .. " máx [" .. QU[q]() .. "]", fmt(g.mx.v, tol), "E" .. g.mx.e, fmt(g.mx.x)}
    D.rows[#D.rows + 1] = {QN[q] .. " mín", fmt(g.mn.v, tol), "E" .. g.mn.e, fmt(g.mn.x)}
  end
  local dm = RES.dmax
  D.rows[#D.rows + 1] = {"|Δ| total máx", fmt(dm.v), "E" .. dm.e, fmt(dm.x)}
  if RES.sym then D.info = "Con valores de prueba: " .. symTxt() end
  return D
end

local function Table(kind)
  local s = {top = 1}
  function s:onEnter() if ensure() then self.D = BUILD[kind]() end end
  function s:paint(gc)
    if not self.D then pop(); return end
    local D = self.D
    cabecera(gc, D.title)
    local y = 30
    if D.info then
      bx(gc, 4, y, W - 8, 16, C.sec)
      font(gc, 9, "b"); cc(gc, C.ac); txt(gc, D.info, 9, y + 1)
      y = y + 19
    end
    local cx = {8, 84, 162, 240}
    bx(gc, 4, y, W - 8, 18, C.hd)
    font(gc, 9, "b"); cc(gc, C.w)
    for j, h in ipairs(D.head) do
      if tw(gc, h) > 76 then font(gc, 7, "b") end
      txt(gc, h, cx[j], y + 2)
      font(gc, 9, "b")
    end
    y = y + 20
    local RH = 17
    local N = max(1, floor((H - 20 - y) / RH))
    local n = #D.rows
    self.N, self.n = N, n
    if self.top > max(1, n - N + 1) then self.top = max(1, n - N + 1) end
    for i = self.top, min(n, self.top + N - 1) do
      local r = D.rows[i]
      local yy = y + (i - self.top) * RH
      local ult = D.last and i == n
      if ult then bx(gc, 4, yy, W - 8, RH, C.sel)
      elseif (i - self.top) % 2 == 1 then bx(gc, 4, yy, W - 8, RH, C.alt) end
      font(gc, 9, ult and "b" or "r")
      for j = 1, #r do
        cc(gc, ult and C.ok or C.tx)
        local st = tostring(r[j])
        local wcol = (cx[j + 1] or W - 4) - cx[j] - 3
        if tw(gc, st) > wcol then font(gc, 7, ult and "b" or "r") end
        txt(gc, st, cx[j], yy + 2)
        font(gc, 9, ult and "b" or "r")
      end
    end
    barra(gc, self.top, n, N, y, N * RH)
    pie(gc, n .. " filas   flechas: desplazar   esc: volver")
  end
  function s:arrow(k)
    if not self.D then return end
    if k == "down" and self.top + (self.N or 8) - 1 < (self.n or 0) then self.top = self.top + 1
    elseif k == "up" and self.top > 1 then self.top = self.top - 1 end
  end
  return s
end

------------------------------------------------------------------
-- Resumen de la solucion
------------------------------------------------------------------
local function Summary()
  return Res("Solución", function()
    if not ensure() then error("No se pudo resolver") end
    local rows = {}
    local GI = RES.GI
    local tit = (GI == 0) and "ISOSTÁTICA" or ("HIPERESTÁTICA grado " .. GI)
    rows[#rows + 1] = {"#", "MODELO"}
    rows[#rows + 1] = {"Nudos / elementos", #M.nodes .. " / " .. #M.elems}
    rows[#rows + 1] = {"GI = 3m + r - 3n - c", tostring(GI)}
    rows[#rows + 1] = {"Unidades", uF() .. ", " .. uL()}
    rows[#rows + 1] = {"#", "REACCIONES"}
    local ref = 0
    for _, r in pairs(RES.RX) do ref = max(ref, abs(r[1]), abs(r[2]), abs(r[3])) end
    local tol = 1e-9 * ref
    local function rv(k, a) return Lstr(SYMV(function(R) return R.RX[k][a] end), tol) end
    local function rsum(a) return Lstr(SYMV(function(R) local s = 0; for _, r in pairs(R.RX) do s = s + r[a] end; return s end), tol) end
    for k = 1, #M.nodes do
      local r = RES.RX[k]
      if r then
        local rs = SUP[M.nodes[k].sup].r
        local p = M.nodes[k]
        if rs[1] == 1 or p.kx > 0 then rows[#rows + 1] = {"N" .. k .. "  Rx", rv(k, 1) .. " " .. uF()} end
        if rs[2] == 1 or p.ky > 0 then rows[#rows + 1] = {"N" .. k .. "  Ry", rv(k, 2) .. " " .. uF()} end
        if rs[3] == 1 or p.kr > 0 then rows[#rows + 1] = {"N" .. k .. "  M", rv(k, 3) .. " " .. uM()} end
      end
    end
    rows[#rows + 1] = {"ΣRx  /  ΣRy", rsum(1) .. "  /  " .. rsum(2)}
    if RES.sym then
      rows[#rows + 1] = {"#", "INCÓGNITAS"}
      for _, k in ipairs(RES.sym.names) do rows[#rows + 1] = {"Valor de prueba " .. k, fmt(ENV[k] or 0)} end
      rows[#rows + 1] = {"~", "Máximos y diagramas usan estos valores."}
      rows[#rows + 1] = {"~", "Cámbielos en MODELO > Incógnitas."}
    end
    rows[#rows + 1] = {"#", "MÁXIMOS"}
    for q = 1, 5 do
      local g = RES.gx[q]
      local t = 1e-9 * RES.qmax[q]
      local a, b = g.mx, g.mn
      local big = (abs(a.v) >= abs(b.v)) and a or b
      rows[#rows + 1] = {QN[q] .. " máx |" .. QN[q] .. "|", fmt(big.v, t) .. " " .. QU[q]() .. "  (E" .. big.e .. ", x=" .. fmt(big.x, nil, 4) .. ")"}
    end
    rows[#rows + 1] = {"|Δ| total", fmt(RES.dmax.v) .. " " .. uL() .. "  (E" .. RES.dmax.e .. ")"}
    return {head = {"Clasificación (estable)", tit}, rows = rows,
            foot = "enter: diagramas   flechas: desplazar   esc: volver"}
  end, {enter = function() push(Canvas(5)) end})
end

------------------------------------------------------------------
-- Ejemplos
------------------------------------------------------------------
local EXAMPLES = {}
EXAMPLES[1] = {"Viga simple, w = -10 kN/m", function()
  local m = newModel()
  m.nodes = {nd(0, 0, 3), nd(6, 0, 4)}
  m.elems = {{i = 1, j = 2, s = 1, hi = 1, hj = 1}}
  m.el = {{e = 1, t = 1, d = 1, v1 = -10, v2 = -10, a = 0, b = 0}}
  return m end}
EXAMPLES[2] = {"Marco empotrado (hiperest.)", function()
  local m = newModel()
  m.nodes = {nd(0, 0, 2), nd(0, 4, 1), nd(6, 4, 1), nd(6, 0, 2)}
  m.elems = {{i = 1, j = 2, s = 1, hi = 1, hj = 1}, {i = 2, j = 3, s = 1, hi = 1, hj = 1}, {i = 3, j = 4, s = 1, hi = 1, hj = 1}}
  m.nl = {{n = 2, fx = 20, fy = 0, m = 0}}
  m.el = {{e = 2, t = 1, d = 1, v1 = -15, v2 = -15, a = 0, b = 0}}
  return m end}
EXAMPLES[3] = {"Viga continua 2 tramos", function()
  local m = newModel()
  m.nodes = {nd(0, 0, 3), nd(5, 0, 4), nd(10, 0, 4)}
  m.elems = {{i = 1, j = 2, s = 1, hi = 1, hj = 1}, {i = 2, j = 3, s = 1, hi = 1, hj = 1}}
  m.el = {{e = 1, t = 1, d = 1, v1 = -12, v2 = -12, a = 0, b = 0}, {e = 2, t = 1, d = 1, v1 = -12, v2 = -12, a = 0, b = 0},
          {e = 2, t = 2, d = 1, v1 = -30, v2 = 0, a = 2.5, b = 0}}
  return m end}
EXAMPLES[4] = {"Viga Gerber (con rótula)", function()
  local m = newModel()
  m.nodes = {nd(0, 0, 2), nd(4, 0, 1), nd(8, 0, 4)}
  m.elems = {{i = 1, j = 2, s = 1, hi = 1, hj = 2}, {i = 2, j = 3, s = 1, hi = 1, hj = 1}}
  m.el = {{e = 1, t = 1, d = 1, v1 = -10, v2 = -10, a = 0, b = 0}, {e = 2, t = 2, d = 1, v1 = -20, v2 = 0, a = 2, b = 0}}
  return m end}
EXAMPLES[5] = {"Marco a dos aguas biartic.", function()
  local m = newModel()
  m.nodes = {nd(0, 0, 3), nd(0, 4, 1), nd(5, 6, 1), nd(10, 4, 1), nd(10, 0, 3)}
  m.elems = {{i = 1, j = 2, s = 1, hi = 1, hj = 1}, {i = 2, j = 3, s = 1, hi = 1, hj = 1},
             {i = 3, j = 4, s = 1, hi = 1, hj = 1}, {i = 4, j = 5, s = 1, hi = 1, hj = 1}}
  m.el = {{e = 2, t = 1, d = 5, v1 = -8, v2 = -8, a = 0, b = 0}, {e = 3, t = 1, d = 5, v1 = -8, v2 = -8, a = 0, b = 0},
          {e = 1, t = 1, d = 2, v1 = 3, v2 = 3, a = 0, b = 0}}
  return m end}

EXAMPLES[6] = {"Viga con carga P (incógnita)", function()
  local m = newModel()
  m.nodes = {nd(0, 0, 3), nd(6, 0, 4)}
  m.elems = {{i = 1, j = 2, s = 1, hi = 1, hj = 1}}
  m.el = {{e = 1, t = 2, d = 1, v1 = {c = 0, s = {P = -1}}, v2 = 0, a = 2, b = 0},
          {e = 1, t = 1, d = 1, v1 = -10, v2 = -10, a = 0, b = 0}}
  m.symv = {P = 1}
  return m end}

local function loadModel(m)
  M = m; fixModel(); RES = nil
  VIEW.zoom, VIEW.px, VIEW.py = 1, 0, 0
end

local function ExamplesMenu()
  local items = {{"Nuevo modelo (vacío)", function()
    showMsg("¿Borrar el modelo actual\ny empezar uno nuevo?", function()
      local fu, lu = M.fu, M.lu
      loadModel(newModel()); M.fu, M.lu = fu, lu
      pop()
    end, true) end}}
  for _, ex in ipairs(EXAMPLES) do
    items[#items + 1] = {ex[1], function()
      showMsg("Se reemplazará el modelo\nactual por el ejemplo.", function()
        loadModel(ex[2]()); pop(); push(Canvas(1))
      end, true) end}
  end
  return Menu("Ejemplos", items, "enter: cargar   esc: volver")
end

------------------------------------------------------------------
-- Inicio
------------------------------------------------------------------
local function About()
  return Res("Acerca de", function()
    return {head = {"Estruc-TI  v" .. VERSION .. "  (antes MARCOS 2D)", "© 2026 " .. AUTOR},
      rows = {
        {"#", "CRÉDITOS"},
        {"~", "Todos los derechos reservados."},
        {"~", "Basado en la app FEES del Ing. Sergio Lobo"},
        {"~", "Aguilar, docente de la Universidad de Costa Rica."},
        {"~", "Desarrollado con ayuda de la IA Claude (Anthropic)."},
        {"#", "NOVEDADES v1.2"},
        {"~", "Cargas incógnitas: escriba P, -2P, w, P/2..."},
        {"~", "en el valor de una carga. Resultados en función"},
        {"~", "de ellas y opción 'Despejar incógnita'."},
        {"#", "MÉTODO"},
        {"~", "Método directo de rigidez, 3 GDL por nudo."},
        {"~", "Diagramas por integración exacta por tramos."},
        {"#", "SIGNOS DE ENTRADA"},
        {"~", "Izquierda, abajo y horario son negativos."},
      }}
  end)
end

------------------------------------------------------------------
-- Incognitas: valores de prueba y despeje
------------------------------------------------------------------
local function SymForm()
  local names = modelSyms()
  if #names == 0 then
    showMsg("No hay incógnitas en el modelo.\nEscriba una letra en el valor de\nuna carga: P, -2P, w, P/2, 3+P...")
    return
  end
  if type(M.symv) ~= "table" then M.symv = {} end
  local fields, rec = {}, {}
  for _, k in ipairs(names) do
    fields[#fields + 1] = {k = k, l = "Valor de prueba de " .. k, t = "n"}
    rec[k] = M.symv[k] or 1
  end
  push(Form("Incógnitas", fields, rec, function(r)
    for _, k in ipairs(names) do M.symv[k] = r[k] end
    dirty()
  end))
end

local DMAG = {"Reacción Rx", "Reacción Ry", "Reacción M", "Nudo Δx", "Nudo Δy", "Nudo θ",
              "N(x) en elemento", "V(x) en elemento", "M(x) en elemento", "θ(x) en elemento", "δ(x) en elemento"}
local DUNIT = {uF, uF, uM, uL, uL, uRad, uF, uF, uM, uRad, uL}

-- Funcion que lee la magnitud elegida de una solucion
local function getter(mag, idx, x)
  if mag <= 6 then
    if not M.nodes[idx] then error("El nudo " .. idx .. " no existe", 0) end
    if mag <= 3 then
      if not RES.RX[idx] then error("El nudo " .. idx .. " no tiene apoyo", 0) end
      return function(R) return R.RX[idx][mag] end
    end
    local b = 3 * (idx - 1) + (mag - 3)
    return function(R) return R.d[b] end
  end
  if not M.elems[idx] then error("El elemento " .. idx .. " no existe", 0) end
  local L = RES.EL[idx].ctx.L
  if x > L * (1 + 1e-9) then error("x supera L = " .. fmt(L), 0) end
  local q = mag - 6
  return function(R) local X = R.EL[idx]; local Lf = query(X.ctx, X.S0, x); return Lf[q] end
end

-- Valor de la incognita 'name' para que la magnitud sea 'target'
local function despejar(mag, idx, x, target, name)
  if not RES.sym then error("El modelo no tiene incógnitas", 0) end
  local f = SYMV(getter(mag, idx, x))
  local b = f.s[name] or 0
  local a = f.c
  for k, v in pairs(f.s) do if k ~= name then a = a + v * (ENV[k] or 0) end end
  local scale = max(Lmag(f), abs(target), 1e-30)
  local sc = abs(ENV[name] or 1); if sc < 1 then sc = 1 end
  if abs(b) * sc < 1e-10 * scale then error("La magnitud no depende de " .. name, 0) end
  return (target - a) / b, f
end

local function SolveForForm()
  if not ensure() then return end
  if not RES.sym then
    showMsg("No hay incógnitas en el modelo.\nEscriba una letra en el valor de\nuna carga: P, -2P, w, P/2...")
    return
  end
  local names = RES.sym.names
  push(Form("Despejar incógnita", {
    {k = "mag", l = "Magnitud", t = "c", o = DMAG},
    {k = "idx", l = function(r) return r.mag <= 6 and "Nudo" or "Elemento" end, t = "i",
     mx = function() return max(#M.nodes, #M.elems) end},
    {k = "x", l = function(r) return r.mag <= 6 and "(x no aplica)" or "x desde el nudo i" end, t = "n",
     u = function(r) return r.mag <= 6 and "" or uL() end, nn = true},
    {k = "obj", l = "Valor deseado", t = "n", u = function(r) return DUNIT[r.mag]() end},
    {k = "inc", l = "Despejar", t = "c", o = names},
  }, {mag = 2, idx = 1, x = 0, obj = 0, inc = 1}, function(r)
    local name = names[r.inc]
    local ok, val, f = pcall(despejar, r.mag, r.idx, r.x, r.obj, name)
    if not ok then return tostring(val) end
    local where = (r.mag <= 6) and ("N" .. r.idx) or ("E" .. r.idx .. ", x=" .. fmt(r.x))
    local tol = 1e-9 * max(Lmag(f), 1e-30)
    local rows = {
      {"#", "CONDICIÓN"},
      {"Magnitud", DMAG[r.mag] .. " (" .. where .. ")"},
      {"=", "= " .. Lstr(f, tol) .. " " .. DUNIT[r.mag]()},
      {"Valor deseado", fmt(r.obj) .. " " .. DUNIT[r.mag]()},
      {"#", "RESULTADO"},
      {name, fmt(val, nil, 6)},
    }
    if #names > 1 then
      rows[#rows + 1] = {"~", "Las otras incógnitas usan su valor de prueba."}
    end
    rows[#rows + 1] = {"~", name .. " en las unidades de la carga donde aparece."}
    stack[#stack] = Res("Despeje", function()
      return {head = {"Para " .. DMAG[r.mag] .. " = " .. fmt(r.obj), name .. " = " .. fmt(val, nil, 6)},
              rows = rows, foot = "enter: usar como valor de prueba   esc: volver"}
    end, {enter = function()
      M.symv[name] = val
      dirty()
      pop()
      showMsg("Valor de prueba actualizado:\n" .. name .. " = " .. fmt(val, nil, 6))
    end})
    inv()
    return "__keep"
  end, "DESPEJAR"))
end

local function doSolve()
  RES = nil
  if ensure() then push(Summary()) end
end

local function needRes(f) return function() if ensure() then f() end end end

local function goPoint()
  if not ensure() then return end
  push(Form("Punto de interés", {
    {k = "e", l = "Elemento", t = "i", mx = function() return #M.elems end},
    {k = "x", l = "x desde el nudo i", t = "n", u = uL, nn = true},
  }, {e = 1, x = 0}, function(r)
    local L = RES.EL[r.e].ctx.L
    if r.x > L * (1 + 1e-9) then return "x supera L = " .. fmt(L) end
    stack[#stack] = ElemView(r.e, 3, min(r.x, L))
    inv()
    return "__keep"
  end, "VER PUNTO"))
end

local HomeItems = {
  {"MODELO", nil, hd = true},
  {"Unidades y opciones", function() push(UnitsForm()) end},
  {"Nudos y apoyos", function() push(List("nodes")) end},
  {"Secciones (E, A, I)", function() push(List("secs")) end},
  {"Elementos y rótulas", function() push(List("elems")) end},
  {"Cargas en nudos", function() push(List("nl")) end},
  {"Cargas en elementos", function() push(List("el")) end},
  {"Incógnitas (P, w...)", SymForm},
  {"Ver modelo", function() push(Canvas(1)) end},
  {"SOLUCIÓN", nil, hd = true},
  {"RESOLVER", doSolve},
  {"Diagramas en el marco", needRes(function() push(Canvas(5)) end)},
  {"Diagrama por elemento", needRes(function() push(ElemView(1, 3, 0)) end)},
  {"Ecuaciones por tramo", needRes(function() push(EqView(1)) end)},
  {"Punto de interés (x)", goPoint},
  {"Despejar incógnita", SolveForForm},
  {"Reacciones", needRes(function() push(Table("reac")) end)},
  {"Desplazamientos", needRes(function() push(Table("disp")) end)},
  {"Fuerzas en extremos", needRes(function() push(Table("ends")) end)},
  {"Máximos y mínimos", needRes(function() push(Table("max")) end)},
  {"OTROS", nil, hd = true},
  {"Ejemplos / nuevo modelo", function() push(ExamplesMenu()) end},
  {"Acerca de", function() push(About()) end},
}

local Home = Menu("Estruc-TI  v" .. VERSION, HomeItems, "© 2026 Juan Vargas    enter: elegir   menu: más")

------------------------------------------------------------------
-- Menu de la calculadora (tecla menu)
------------------------------------------------------------------
local function goto0(f) return function() MSG = nil; stack = {Home}; f(); inv() end end
local function noop() end

if toolpalette and toolpalette.register then
  toolpalette.register({
    {"Archivo",
      {"Inicio", goto0(noop)},
      {"Ejemplos / Nuevo", goto0(function() push(ExamplesMenu()) end)},
      {"Acerca de", goto0(function() push(About()) end)}},
    {"Modelo",
      {"Unidades y opciones", goto0(function() push(UnitsForm()) end)},
      {"Nudos y apoyos", goto0(function() push(List("nodes")) end)},
      {"Secciones", goto0(function() push(List("secs")) end)},
      {"Elementos", goto0(function() push(List("elems")) end)},
      {"Cargas en nudos", goto0(function() push(List("nl")) end)},
      {"Cargas en elementos", goto0(function() push(List("el")) end)},
      {"Incognitas (P, w...)", goto0(SymForm)},
      {"Ver modelo", goto0(function() push(Canvas(1)) end)}},
    {"Resultados",
      {"Resolver", goto0(doSolve)},
      {"Diagramas", goto0(needRes(function() push(Canvas(5)) end))},
      {"Por elemento", goto0(needRes(function() push(ElemView(1, 3, 0)) end))},
      {"Ecuaciones", goto0(needRes(function() push(EqView(1)) end))},
      {"Punto de interes", goto0(goPoint)},
      {"Despejar incognita", goto0(SolveForForm)},
      {"Reacciones", goto0(needRes(function() push(Table("reac")) end))},
      {"Desplazamientos", goto0(needRes(function() push(Table("disp")) end))},
      {"Fuerzas en extremos", goto0(needRes(function() push(Table("ends")) end))},
      {"Maximos", goto0(needRes(function() push(Table("max")) end))}},
  })
end

stack = {Home}

------------------------------------------------------------------
-- Eventos
------------------------------------------------------------------
local function safe(fn)
  local ok, err = pcall(fn)
  if not ok then MSG = {text = "Error:\n" .. tostring(err)} end
  inv()
end

local function drawMsg(gc)
  local lines = {}
  for l in (MSG.text .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = l end
  font(gc, 10)
  local wmax = 150
  for _, l in ipairs(lines) do wmax = max(wmax, tw(gc, l)) end
  local bw = min(W - 16, wmax + 24)
  local bh = #lines * 15 + 48
  local x, y = floor((W - bw) / 2), max(28, floor((H - bh) / 2))
  bx(gc, x + 3, y + 3, bw, bh, C.ln)
  bx(gc, x, y, bw, bh, C.w)
  bx(gc, x, y, bw, 20, MSG.confirm and C.hd or (MSG.text:find("Error") and C.err or C.hd))
  bx(gc, x, y + 20, bw, 2, C.ac)
  font(gc, 10, "b"); cc(gc, C.w)
  txt(gc, MSG.confirm and "Confirmar" or "Aviso", x + 8, y + 2)
  font(gc, 10); cc(gc, C.tx)
  for i, l in ipairs(lines) do txt(gc, l, x + 10, y + 26 + (i - 1) * 15) end
  bx(gc, x, y + bh - 18, bw, 18, C.ft)
  font(gc, 9); cc(gc, C.sub)
  txtR(gc, MSG.confirm and "enter: sí   esc: no" or "enter / esc: cerrar", x + bw - 8, y + bh - 16)
end

function on.resize(w, h) W, H = w, h end

function on.paint(gc)
  W, H = platform.window:width(), platform.window:height()
  if W < 50 then W, H = 318, 212 end
  bx(gc, 0, 0, W, H, C.bg)
  local ok, err = pcall(function() cur():paint(gc) end)
  if not ok then
    cc(gc, C.err); font(gc, 9)
    txt(gc, "Error de dibujo:", 4, 40)
    font(gc, 7); txt(gc, tostring(err):sub(1, 60), 4, 56); txt(gc, tostring(err):sub(61, 120), 4, 66)
  end
  if MSG then pcall(drawMsg, gc) end
end

local function key(name, ...)
  local args = {...}
  safe(function()
    if MSG then
      if name == "kEnter" then local f = MSG.ok; MSG = nil; if f then f() end
      elseif name == "kEsc" then MSG = nil end
      return
    end
    local s = cur()
    if name == "kEsc" then
      if s.kEsc then s:kEsc() else pop() end
      return
    end
    if s[name] then s[name](s, args[1]) end
  end)
end

function on.enterKey() key("kEnter") end
function on.returnKey() key("kEnter") end
function on.escapeKey() key("kEsc") end
function on.arrowKey(k) key("arrow", k) end
function on.tabKey() key("tab") end
function on.backtabKey() key("backtab") end
function on.backspaceKey() key("back") end
function on.deleteKey() key("del") end
function on.clearKey() key("clear") end
function on.charIn(ch) key("char", ch) end

function on.save()
  return {m = ser(M)}
end

function on.restore(st)
  if type(st) == "table" and type(st.m) == "string" then
    local ok, m = pcall(deser, st.m)
    if ok and type(m) == "table" and type(m.nodes) == "table" then loadModel(m) end
  end
  inv()
end

-- Acceso para pruebas en PC (no afecta el uso en la calculadora)
MARCOS2D = {solve = solve, query = query, setModel = function(m) loadModel(m) end,
            getModel = function() return M end, ser = ser, deser = deser, examples = EXAMPLES,
            key = key, stack = function() return stack end, push = push,
            Canvas = Canvas, Table = Table, ElemView = ElemView, List = List, UnitsForm = UnitsForm,
            ExamplesMenu = ExamplesMenu, res = function() return RES end, ensure = ensure,
            msg = function() return MSG end, fmt = fmt, tramos = tramos, polyEval = polyEval,
            EqView = EqView, Summary = Summary, About = About, polyStr = polyStr,
            Lparse = Lparse, Lstr = Lstr, SYMV = SYMV, despejar = despejar, modelSyms = modelSyms,
            tramosL = tramosL, SymForm = SymForm, SolveForForm = SolveForForm, Lval = Lval}
