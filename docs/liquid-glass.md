# Liquid Glass in Dynamic Island

How the "Liquid Glass" material of this project was designed: what Apple says it is, what we can
and cannot do on a Wayland desktop, and how each idea maps to a component.

## What Liquid Glass is (research)

Sources: Apple's WWDC25 session [Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219)
(transcript), the [kube.io article on refraction with CSS and SVG](https://kube.io/blog/liquid-glass-css-svg),
[Wikipedia](https://en.wikipedia.org/wiki/Liquid_Glass) and several adoption guides. Apple's HIG pages are
rendered with JavaScript and could not be read, so the rules below come from the session transcript.

| Property | What Apple describes | Our version |
|---|---|---|
| **Lensing** | the defining property: the material *bends and concentrates* light instead of scattering it | refraction shader on a rounded-rectangle height field |
| **Specular highlights** | lights in the scene produce highlights that follow the geometry and move with interaction | rim light, lit side + faint opposite side, direction follows the pointer |
| **Adaptive shadow** | shadow opacity rises over text and falls over plain light backgrounds | soft shadow whose strength follows the backdrop luminance |
| **Tint** | not a flat fill: a range of tones mapped to the brightness of what is behind | tint mixed by backdrop luma, never an opaque colour |
| **Light / dark adaptation** | small elements flip, large ones do not | small glass lifts or darkens with the backdrop, the island body keeps its character |
| **Thickness grows with size** | larger glass: deeper shadow, stronger lensing, softer scatter | bezel and thickness are derived from the element's size |
| **Illumination on press** | glows from within, starting under the finger and spreading to neighbours | glow uniform centred on the pointer, neighbours get a faint share |
| **Gel-like flex / morph** | shapes flex and merge, the resting state is calm | liquid pill (two springs), split island with a neck |
| **Materialization** | objects do not fade: their lensing is modulated in and out | `lens` goes 0 → 1 with a little blur, scale and a rim flash |
| **Concentricity** | glass nests into the rounded corners around it | inner radii = outer radius − padding |
| **Regular vs Clear** | regular adapts and is legible anywhere; clear needs a dimming layer; never mix | we ship *Regular*; "Clear" is the low-frost preset with a dimming layer |
| **Layering** | glass is the navigation/controls layer above content; **no glass on glass**; don't tint everything | island body = one glass slab; inner cards use the thin variant (rim only), controls use full lensing |
| **Accessibility** | Reduce Transparency → frostier; Increase Contrast → black/white + border; Reduce Motion → fewer effects, no elasticity | `frost`, high-contrast and reduced-motion fallbacks (see below) |

### The physics we reimplement

From the kube.io article (Snell's law, n = 1.5) and Apple's squircle preference:

```
bezel height     h(t) = (1 - (1 - t)^4)^(1/4)          t = distance from the edge / bezel width
slope            h'(t) = (1 - t)^3 / (1 - (1 - t)^4)^(3/4)
surface normal   N = normalize( n_out * slope, 1 )      n_out = gradient of the rounded-box SDF
refraction       R = refract(I = (0, 0, -1), N, 1 / 1.5)
displacement     d = R.xy / -R.z * (height + gap)       sample the backdrop at p + d
```

Everything is evaluated per pixel in a fragment shader from the signed distance of a rounded rectangle, so
one shader covers every size and corner radius (`shaders/glass.frag`).

## What a Wayland desktop allows

* **Content behind the island is not readable.** A layer-shell surface cannot sample the desktop, so the
  *lens* bends the island's own backdrop (accent colours, album artwork): what sits behind controls
  inside the island. This is also what Apple's controls do: they bend the content layer under them.
* **The island body can still be real glass.** KWin's blur can be requested for a window with
  `KWindowEffects::enableBlurBehind`. KDE's QML bindings do not expose it, so a tiny optional native
  plugin (`native/`) requests it for the island shape. Without it the body is a tinted, frosted slab:
  still legible, just not see-through.
* **Specular + rim + tint + lensing** are drawn by our shader on top of whatever the compositor blurred.

## Component map

* `shaders/glass.frag` → `glass.frag.qsb`: the material.
* `GlassSurface.qml`: one glass element (lens strength, frost, tint, rim, glow, light direction).
* `GlassBackdrop.qml`: the island's inner "content layer" that glass samples (shared texture).
* `GlassCard.qml`, `GlassButton.qml`, glass `Switch`/`IslandSlider` knob, `LiquidPill`: the controls.
* Not shipped yet: `BlurBehind` (native plugin asking KWin to blur what is behind the island). The body is a frosted slab over the island's own backdrop until then.
* Settings → Appearance → Material → **Liquid Glass**, with *Frosted / Balanced / Clear* presets.

## Rules we hold ourselves to

1. Glass for controls and navigation only; text blocks and lists stay on the content layer.
2. No glass on glass: cards use the *thin* variant (rim + faint tint, no lensing).
3. Colour is for primary actions; everything else is neutral.
4. Contrast first: text over glass keeps ≥ 4.5:1 (frost rises automatically over busy backdrops).
5. Motion explains change: materialization instead of fades, no decorative loops.
6. Accessibility fallbacks are part of the material, not an afterthought.
