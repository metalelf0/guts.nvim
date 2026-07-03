-- OKLCH color transformation utilities (Björn Ottosson, 2020)
-- Converts sRGB hex <-> OKLCH and applies perceptual chroma boost.
-- Out-of-gamut results are brought back by bisecting chroma down
-- while keeping Lightness and Hue fixed.

local M = {}

-- ── sRGB ↔ linear ────────────────────────────────────────────────────────────

local function to_linear(c)
	if c <= 0.04045 then
		return c / 12.92
	else
		return ((c + 0.055) / 1.055) ^ 2.4
	end
end

local function to_srgb(c)
	if c <= 0.0031308 then
		return c * 12.92
	else
		return 1.055 * c ^ (1 / 2.4) - 0.055
	end
end

-- ── Hex ↔ [0,1] sRGB ─────────────────────────────────────────────────────────

local function hex_to_rgb(hex)
	hex = hex:gsub("#", "")
	return {
		r = tonumber(hex:sub(1, 2), 16) / 255,
		g = tonumber(hex:sub(3, 4), 16) / 255,
		b = tonumber(hex:sub(5, 6), 16) / 255,
	}
end

local function clamp01(x)
	return math.max(0, math.min(1, x))
end

local function rgb_to_hex(r, g, b)
	return string.format(
		"#%02x%02x%02x",
		math.floor(clamp01(r) * 255 + 0.5),
		math.floor(clamp01(g) * 255 + 0.5),
		math.floor(clamp01(b) * 255 + 0.5)
	)
end

-- ── cube root that handles negative values ────────────────────────────────────

local function cbrt(x)
	if x >= 0 then
		return x ^ (1 / 3)
	else
		return -((-x) ^ (1 / 3))
	end
end

-- ── Linear RGB ↔ OKLab ───────────────────────────────────────────────────────
-- Matrices from https://bottosson.github.io/posts/oklab/

local function linear_to_oklab(r, g, b)
	local l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
	local m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
	local s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b

	local l_ = cbrt(l)
	local m_ = cbrt(m)
	local s_ = cbrt(s)

	return {
		L = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
		a = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
		b = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_,
	}
end

local function oklab_to_linear(L, aa, bb)
	local l_ = L + 0.3963377774 * aa + 0.2158037573 * bb
	local m_ = L - 0.1055613458 * aa - 0.0638541728 * bb
	local s_ = L - 0.0894841775 * aa - 1.2914855480 * bb

	local l = l_ * l_ * l_
	local m = m_ * m_ * m_
	local s = s_ * s_ * s_

	return {
		r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
		g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
		b = -0.0041960863 * l - 0.7034186147 * m + 1.6076135658 * s,
	}
end

-- ── OKLab ↔ OKLCH ────────────────────────────────────────────────────────────

local function oklab_to_oklch(lab)
	local C = math.sqrt(lab.a * lab.a + lab.b * lab.b)
	local h = math.atan2(lab.b, lab.a)
	return lab.L, C, h
end

local function oklch_to_oklab(L, C, h)
	return L, C * math.cos(h), C * math.sin(h)
end

-- ── Gamut check ──────────────────────────────────────────────────────────────

local GAMUT_EPS = 1e-4

local function srgb_in_gamut(r, g, b)
	return r >= -GAMUT_EPS
		and r <= 1 + GAMUT_EPS
		and g >= -GAMUT_EPS
		and g <= 1 + GAMUT_EPS
		and b >= -GAMUT_EPS
		and b <= 1 + GAMUT_EPS
end

-- Convert OKLCH → sRGB (unclamped, for gamut checks)
local function oklch_to_srgb(L, C, h)
	local la, aa, bb = oklch_to_oklab(L, C, h)
	local lin = oklab_to_linear(la, aa, bb)
	return to_srgb(lin.r), to_srgb(lin.g), to_srgb(lin.b)
end

-- Bisect chroma down until the result is inside the sRGB gamut.
-- Keeps L and h fixed. Runs at most 30 iterations (~1e-9 precision).
local function map_to_gamut(L, C, h)
	local lo, hi = 0.0, C
	for _ = 1, 30 do
		local mid = (lo + hi) * 0.5
		local r, g, b = oklch_to_srgb(L, mid, h)
		if srgb_in_gamut(r, g, b) then
			lo = mid
		else
			hi = mid
		end
	end
	return lo
end

-- ── Public API ────────────────────────────────────────────────────────────────

-- Boost the chroma (colourfulness) of a hex colour by `factor` in OKLCH space.
-- Lightness and hue are preserved. Out-of-gamut results are pulled back to the
-- sRGB boundary by reducing chroma (not by clipping channels).
function M.saturate(hex, factor)
	local rgb = hex_to_rgb(hex)
	local lr = to_linear(rgb.r)
	local lg = to_linear(rgb.g)
	local lb = to_linear(rgb.b)

	local lab = linear_to_oklab(lr, lg, lb)
	local L, C, h = oklab_to_oklch(lab)

	local C_new = C * factor

	-- Fast path: already in gamut
	local r, g, b = oklch_to_srgb(L, C_new, h)
	if not srgb_in_gamut(r, g, b) then
		C_new = map_to_gamut(L, C_new, h)
		r, g, b = oklch_to_srgb(L, C_new, h)
	end

	return rgb_to_hex(r, g, b)
end

return M
