#version 440
// Liquid Glass malzemesi (Dynamic Island). docs/liquid-glass.md'de açıklanan fizik:
// yuvarlatılmış dikdörtgenin işaretli uzaklık alanından (SDF) bir kenar profili ("bezel") çıkar,
// yüzey normalinden Snell yasasıyla kırılma ofseti hesapla, arka planı o ofsetle örnekle.
// Derleme: shaders/build.sh  →  glass.frag.qsb
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;          // öğenin boyutu (px)
    vec4 radii;         // köşe yarıçapları: sol-üst, sağ-üst, sağ-alt, sol-alt (px)
    vec4 tint;          // rgb: ton rengi, a: ton yoğunluğu
    vec4 glowColor;     // rgb: içeriden aydınlanma rengi, a: şiddeti (basınca)
    vec2 glowPos;       // aydınlanmanın merkezi (öğe içi px)
    vec2 lightDir;      // ışığa doğru birim vektör (y aşağı)
    vec4 backRect;      // arka plan dokusunda bu öğenin kapladığı dikdörtgen (uv: x, y, w, h)
    float bezel;        // kenar profilinin genişliği (px)
    float thickness;    // cam kalınlığı (px)
    float ior;          // kırılma indisi (1,5)
    float lens;         // 0..1 mercek şiddeti (materialization)
    float frost;        // 0..1 buzlu (bulanık) arka plan karışımı
    float rim;          // özel parlama şiddeti
    float saturation;   // doygunluk çarpanı
    float lift;         // taban parlaklık kayması
    float chroma;       // renk ayrışması (0 = yok)
    float bodyAlpha;    // camın gövde saydamlığı (1 = opak)
    float adapt;        // 0..1 arka plana uyum (açık zeminde koyulaş, koyuda açıl)
};
layout(binding = 1) uniform sampler2D backdrop;       // keskin arka plan
layout(binding = 2) uniform sampler2D backdropBlur;   // bulanık arka plan

float sdRoundBox(vec2 p, vec2 halfSize, vec4 r) {
    float rad = (p.x > 0.0) ? ((p.y > 0.0) ? r.z : r.y) : ((p.y > 0.0) ? r.w : r.x);
    rad = min(rad, min(halfSize.x, halfSize.y));
    vec2 q = abs(p) - halfSize + rad;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - rad;
}

float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

void main() {
    vec2 px = qt_TexCoord0 * size;
    vec2 halfSize = size * 0.5;
    vec2 p = px - halfSize;

    float sd = sdRoundBox(p, halfSize, radii);
    float coverage = 1.0 - smoothstep(-0.75, 0.75, sd);
    if (coverage <= 0.0) { fragColor = vec4(0.0); return; }

    // dış yöne bakan birim vektör: SDF'nin gradyanı (sonlu farklar)
    float e = 0.75;
    vec2 n = vec2(sdRoundBox(p + vec2(e, 0.0), halfSize, radii) - sdRoundBox(p - vec2(e, 0.0), halfSize, radii),
                  sdRoundBox(p + vec2(0.0, e), halfSize, radii) - sdRoundBox(p - vec2(0.0, e), halfSize, radii));
    n = (length(n) > 1e-4) ? normalize(n) : vec2(0.0, -1.0);

    float d = max(-sd, 0.0);                       // kenardan içeri uzaklık (px)
    float B = max(bezel, 1.0);
    float t = clamp(d / B, 0.0, 1.0);

    // squircle kenar profili ve eğimi
    float omt = 1.0 - t;
    float omt4 = omt * omt * omt * omt;
    float h = thickness * pow(max(1.0 - omt4, 1e-4), 0.25);
    float slope = thickness / B * (omt * omt * omt) / pow(max(1.0 - omt4, 1e-3), 0.75);
    slope = min(slope, 5.0);

    // yüzey normali ve Snell kırılması
    vec3 N = normalize(vec3(n * slope, 1.0));
    vec3 R = refract(vec3(0.0, 0.0, -1.0), N, 1.0 / ior);
    float travel = h + 0.55 * thickness;
    vec2 disp = R.xy * (travel / max(-R.z, 0.2)) * lens;   // px cinsinden ofset

    // arka planı kırılmış konumdan örnekle (üç kanal biraz farklı: renk ayrışması)
    vec2 uvR = clamp((px + disp * (1.0 - chroma)) / size, 0.002, 0.998);
    vec2 uvG = clamp((px + disp) / size, 0.002, 0.998);
    vec2 uvB = clamp((px + disp * (1.0 + chroma)) / size, 0.002, 0.998);
    vec2 mapR = backRect.xy + uvR * backRect.zw;
    vec2 mapG = backRect.xy + uvG * backRect.zw;
    vec2 mapB = backRect.xy + uvB * backRect.zw;
    vec3 sharp = vec3(texture(backdrop, mapR).r, texture(backdrop, mapG).g, texture(backdrop, mapB).b);
    vec3 soft = vec3(texture(backdropBlur, mapR).r, texture(backdropBlur, mapG).g, texture(backdropBlur, mapB).b);
    vec3 col = mix(sharp, soft, frost);

    // doygunluk ve uyarlanır parlaklık: koyu zeminde cam açılır, açık zeminde koyulaşır
    float L = luma(col);
    col = mix(vec3(L), col, saturation);
    float shift = lift + adapt * mix(0.10, -0.07, smoothstep(0.30, 0.80, L));
    col += shift;

    // ton (düz dolgu değil: arka planın parlaklığına göre kayar)
    col = mix(col, tint.rgb * (0.55 + 0.9 * L), tint.a);

    // özel parlama: kenarda ince şerit, ışığa dönük yan güçlü, karşı yan hafif
    vec2 ld = normalize(lightDir);
    float lit = pow(max(dot(n, ld), 0.0), 1.4);
    float back = pow(max(dot(n, -ld), 0.0), 2.6) * 0.5;
    float band = 1.0 - smoothstep(0.0, 2.4, d);
    float spec = (lit + back) * band * rim;
    // kalın kenarda geniş, yumuşak bir Fresnel parıltısı
    float fres = pow(1.0 - t, 3.0) * (0.04 + 0.10 * lit) * rim;
    col += vec3(spec + fres) * mix(vec3(1.0), tint.rgb + 0.35, 0.25);

    // basınca içeriden aydınlanma
    float gr = max(min(size.x, size.y) * 0.9, 24.0);
    float g = glowColor.a * exp(-dot(px - glowPos, px - glowPos) / (gr * gr));
    col += glowColor.rgb * g * 0.40;

    float a = coverage * bodyAlpha;
    fragColor = vec4(clamp(col, 0.0, 1.0) * a, a) * qt_Opacity;
}
