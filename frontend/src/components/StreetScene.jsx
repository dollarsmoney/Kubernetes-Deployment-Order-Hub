import { useReducedMotion } from 'framer-motion';

/**
 * StreetScene — an illustrated Lagos street with delivery traffic crossing it.
 *
 * ORIGINAL ARTWORK. Every path in this file was authored for this project.
 * Nothing here is traced from, or derived from, any existing delivery brand's
 * illustration.
 *
 * ---------------------------------------------------------------------------
 * THE SKY IS NOT IN THIS SVG — and that is the important design decision.
 * ---------------------------------------------------------------------------
 * The obvious approach is to draw the sky as a rect inside the viewBox and use
 * `preserveAspectRatio="...slice"` to crop it. That fails badly at hero size:
 *
 *   at 1920px wide, a 1200-unit viewBox scales by 1.6, so EVERYTHING gets 1.6x
 *   taller too. A 620px-tall container then crops ~370px off the top — which
 *   eats the buildings, not just the sky.
 *
 * Instead this SVG contains only the GROUND BAND (skyline, buildings, road,
 * verge), and is anchored to the bottom of the hero at an explicit height set
 * by the caller. The sky is a CSS gradient on the section behind it, which can
 * be any height at all and never crops anything that matters.
 *
 * With `slice`, whatever does get cropped is the TOP of the band — empty space
 * above the rooftops — and the road stays pinned to the bottom edge, which is
 * the part that has to stay visible.
 *
 * ---------------------------------------------------------------------------
 * COORDINATE SYSTEM — viewBox "0 0 2000 420"
 * ---------------------------------------------------------------------------
 *     0 ┌──────────────────────────────────────────┐ transparent (CSS sky)
 *    50 │  ▓ anchor building (RIGHT side only) ▓    │
 *   140 │  ░ distant skyline ░  shops · palms       │
 *   250 ├──────────────────────────────────────────┤ GROUND
 *   260 │  ROAD                                     │
 *   300 │  · · far lane — danfo ←, van parked · · · │
 *   318 │  – – – centre line – – – – – – – – – – –  │
 *   344 │  · · near lane — riders →, keke → · · · · │
 *   362 ├──────────────────────────────────────────┤
 *   374 │  kerb + grass verge                       │
 *   420 └──────────────────────────────────────────┘
 *
 * WHY 2000 UNITS WIDE AND NOT 1200: the viewBox aspect ratio should roughly
 * match the container's. A 1200x420 box (aspect 2.9) inside a 1920x400 strip
 * (aspect 4.8) has to scale by 1.6 to cover the width, which makes everything
 * 1.6x TALLER too and crops the buildings off the top. At 2000x420 (aspect
 * 4.76) the scale is ~0.96 and almost nothing is lost.
 *
 * The `ride` keyframes in tailwind.config.js are tied to this width. Change one
 * without the other and vehicles disappear before reaching the far edge.
 *
 * COMPOSITION RULE: x 0–1260 is kept deliberately LOW (short shops, palms)
 * because the hero headline sits over it. Everything tall — the anchor building
 * — lives beyond x 1280, where there is no copy.
 */

/* ==========================================================================
 * PALETTE — warm Lagos daytime
 * ========================================================================== */
const C = {
  skyline: '#F2C879',

  wallA: '#E8A33D', // mustard
  wallB: '#D9734A', // terracotta
  wallC: '#F2C879', // sand
  roof: '#78350F',

  palmLeaf: '#16A34A',
  palmLeafDark: '#0E7A45',
  palmTrunk: '#92603A',

  road: '#57534E',
  roadDark: '#44403C',
  dash: '#FFF1F2',
  kerb: '#E7E5E4',
  kerbShade: '#D6D3D1',
  grass: '#16A34A',
  grassDark: '#0E7A45',

  ink: '#1C1917',
  ink80: '#292524',
  brand: '#E11D48',
  brandDark: '#BE123C',
  amber: '#FBBF24',
  amberDark: '#D97706',
  teal: '#0E7490',
  tealDark: '#155E75',
  glass: '#BAE0FF',
  skin: '#8B5A3C',
  white: '#FFFFFF',
};

const GROUND = 250; // every building, tree and kerb sits on this line

/* ==========================================================================
 * BUILDINGS
 * ========================================================================== */

/** A low-rise shopfront: signboard, striped awning, roller shutter. */
function Shop({ x, w, h, wall, awning, tank = false, dish = false, storeys = 1 }) {
  const y = GROUND - h;
  const awningY = GROUND - 46;

  return (
    <g>
      <rect x={x} y={y} width={w} height={h} fill={wall} />
      <rect x={x + w - 5} y={y} width={5} height={h} fill={C.ink} opacity="0.09" />
      <rect x={x - 3} y={y} width={w + 6} height={7} rx="1.5" fill={C.roof} opacity="0.7" />

      {storeys > 1 &&
        [0, 1, 2].map((i) => (
          <rect
            key={i}
            x={x + 12 + (i * (w - 24)) / 3}
            y={y + 14}
            width={Math.max(10, (w - 34) / 3.4)}
            height={16}
            rx="2"
            fill={C.glass}
            opacity="0.85"
          />
        ))}

      <rect x={x + 6} y={awningY - 15} width={w - 12} height={12} rx="2" fill={C.ink} opacity="0.82" />

      {/* Striped awning */}
      {/* Positions are computed FIRST and then mapped, so each stripe is keyed
          by its own x coordinate — a value that identifies the thing rather
          than its position in a list.

          `key={x + 2 + i * 11}` looks equivalent and is not: the rule flags any
          key expression that references the loop index, including arithmetic,
          and it is right to. */}
      {Array.from({ length: Math.floor((w - 4) / 11) }, (_, i) => x + 2 + i * 11).map(
        (stripeX, i) => (
          <rect
            key={stripeX}
            x={stripeX}
            y={awningY}
            width={11}
            height={13}
            fill={i % 2 === 0 ? awning : C.white}
          />
        ),
      )}

      {/* Roller shutter */}
      <rect x={x + w / 2 - 16} y={GROUND - 30} width={32} height={30} rx="1.5" fill={C.ink} opacity="0.72" />
      {[0, 1, 2, 3].map((i) => (
        <rect key={i} x={x + w / 2 - 16} y={GROUND - 27 + i * 7} width={32} height={2} fill={C.white} opacity="0.16" />
      ))}

      {tank && (
        <g>
          <rect x={x + w - 30} y={y - 17} width={8} height={17} fill={C.kerbShade} />
          <rect x={x + w - 40} y={y - 29} width={26} height={14} rx="3" fill="#0EA5E9" opacity="0.85" />
          <ellipse cx={x + w - 27} cy={y - 29} rx="13" ry="3.5" fill="#38BDF8" />
        </g>
      )}

      {dish && (
        <g stroke={C.kerbShade} strokeWidth="2" fill="none">
          <path d={`M${x + 12} ${y - 2} v-10`} />
          <ellipse cx={x + 12} cy={y - 15} rx="7.5" ry="5" fill={C.kerbShade} stroke="none" />
          <path d={`M${x + 12} ${y - 15} l5 -4`} />
        </g>
      )}
    </g>
  );
}

/**
 * The anchor building — a 3-storey market block.
 *
 * Its job is compositional: once the scene is hero-sized, a row of equal-height
 * shops reads as a flat repeating strip. One tall irregular mass on the right
 * gives the eye somewhere to land and balances the headline on the left.
 */
function AnchorBuilding({ x, w = 210, h = 200 }) {
  const y = GROUND - h;
  const floor = (h - 60) / 3; // three upper floors above the shopfront

  return (
    <g>
      {/* Mass */}
      <rect x={x} y={y} width={w} height={h} fill={C.wallC} />
      <rect x={x + w - 7} y={y} width={7} height={h} fill={C.ink} opacity="0.1" />

      {/* Parapet + roof trim */}
      <rect x={x - 5} y={y - 8} width={w + 10} height={11} rx="2" fill={C.roof} opacity="0.75" />
      <rect x={x - 5} y={y - 12} width={w + 10} height={5} rx="2" fill={C.wallB} />

      {/* Three floors of balconies */}
      {[0, 1, 2].map((f) => {
        const fy = y + 10 + f * floor;
        return (
          <g key={f}>
            {/* windows */}
            {[0, 1, 2, 3].map((i) => (
              <rect
                key={i}
                x={x + 16 + i * ((w - 32) / 4)}
                y={fy + 6}
                width={(w - 46) / 4.6}
                height={floor * 0.42}
                rx="2"
                fill={C.glass}
                opacity="0.88"
              />
            ))}
            {/* balcony slab + railing */}
            <rect x={x + 6} y={fy + floor * 0.62} width={w - 12} height={5} rx="1.5" fill={C.wallB} />
            {Array.from(
              { length: Math.floor((w - 24) / 12) },
              (_, i) => x + 12 + i * 12,
            ).map((railX) => (
              <rect
                key={railX}
                x={railX}
                y={fy + floor * 0.44}
                width={2.4}
                height={floor * 0.19}
                fill={C.roof}
                opacity="0.5"
              />
            ))}
          </g>
        );
      })}

      {/* Big signboard over the ground floor */}
      <rect x={x + 8} y={GROUND - 56} width={w - 16} height={18} rx="3" fill={C.brand} />
      <rect x={x + 16} y={GROUND - 50} width={w - 60} height={6} rx="3" fill={C.white} opacity="0.55" />

      {/* Stacked awning across the full frontage */}
      {Array.from({ length: Math.floor((w - 6) / 12) }, (_, i) => x + 3 + i * 12).map(
        (panelX, i) => (
          <rect
            key={panelX}
            x={panelX}
            y={GROUND - 36}
            width={12}
            height={14}
            fill={i % 2 === 0 ? C.amber : C.white}
          />
        ),
      )}

      {/* Two shutters, because it is wide enough to need them */}
      {[0.3, 0.68].map((t) => (
        <g key={t}>
          <rect x={x + w * t - 17} y={GROUND - 22} width={34} height={22} rx="1.5" fill={C.ink} opacity="0.72" />
          {[0, 1, 2].map((i) => (
            <rect
              key={i}
              x={x + w * t - 17}
              y={GROUND - 19 + i * 7}
              width={34}
              height={2}
              fill={C.white}
              opacity="0.16"
            />
          ))}
        </g>
      ))}

      {/* Rooftop tank */}
      <rect x={x + w - 46} y={y - 32} width={9} height={20} fill={C.kerbShade} />
      <rect x={x + w - 58} y={y - 46} width={30} height={16} rx="3" fill="#0EA5E9" opacity="0.85" />
      <ellipse cx={x + w - 43} cy={y - 46} rx="15" ry="4" fill="#38BDF8" />
    </g>
  );
}

/** A palm — curved trunk, fronds fanned from the crown. */
function Palm({ x, height = 96, flip = false }) {
  const topY = GROUND - height;
  const lean = flip ? -10 : 10;

  return (
    <g>
      <path
        d={`M${x} ${GROUND} Q${x + lean * 0.4} ${GROUND - height / 2} ${x + lean} ${topY}`}
        stroke={C.palmTrunk}
        strokeWidth="7"
        strokeLinecap="round"
        fill="none"
      />
      {[0.25, 0.45, 0.65, 0.85].map((t) => (
        <circle key={t} cx={x + lean * t} cy={GROUND - height * t} r="3.6" fill={C.palmTrunk} opacity="0.55" />
      ))}
      {[-150, -115, -70, -30, -200, 20].map((deg, i) => (
        <path
          key={deg}
          d="M0 0 Q26 -9 46 -3 Q26 5 0 0 Z"
          transform={`translate(${x + lean} ${topY}) rotate(${deg})`}
          fill={i % 2 === 0 ? C.palmLeaf : C.palmLeafDark}
        />
      ))}
      <circle cx={x + lean} cy={topY} r="4" fill={C.palmLeafDark} />
    </g>
  );
}

/* ==========================================================================
 * VEHICLES
 * ========================================================================== */

/**
 * A spinning wheel.
 *
 * `transformBox: 'fill-box'` + `transformOrigin: 'center'` makes the spokes
 * rotate about their OWN bounding-box centre. Without fill-box the origin
 * defaults to the SVG's (0,0) and the wheel orbits the corner of the whole
 * scene instead of spinning in place.
 */
function Wheel({ cx, cy, r = 9, reduce, spin = true }) {
  return (
    <g>
      <circle cx={cx} cy={cy} r={r} fill={C.ink} />
      <circle cx={cx} cy={cy} r={r * 0.5} fill={C.kerbShade} />
      <path
        d={`M${cx - r * 0.62} ${cy} H${cx + r * 0.62} M${cx} ${cy - r * 0.62} V${cy + r * 0.62}`}
        stroke={C.kerbShade}
        strokeWidth="1.4"
        strokeLinecap="round"
        // `spin` is about the VEHICLE (the parked van never spins); `reduce` is
        // about the VIEWER. Two different reasons to hold still, so two flags —
        // collapsing them into one would mean the van only stopped spinning for
        // people with reduced motion enabled.
        className={spin && !reduce ? 'animate-spin-wheel' : undefined}
        style={{ transformBox: 'fill-box', transformOrigin: 'center' }}
      />
    </g>
  );
}

/** The Jollof Run rice-grain-arrow mark, as it appears on a delivery box. */
function BoxMark({ x, y, size = 15 }) {
  // Same path as components/Logo.jsx, authored on a 48x48 grid — scaled rather
  // than redrawn, so the box and the navbar logo can never drift apart.
  return (
    <g transform={`translate(${x} ${y}) scale(${size / 48})`}>
      <path
        d="M11 33.5c5.4-1.6 9.1-4 12.4-7.3 3.3-3.3 5.7-7 7.3-12.4l6.3 6.3c-1.6 5.4-4 9.1-7.3 12.4-3.3 3.3-7 5.7-12.4 7.3z"
        fill={C.white}
      />
      <circle cx="32.5" cy="15.5" r="3.4" fill={C.amber} />
    </g>
  );
}

/**
 * Shared wrapper for anything that drives across the scene.
 *
 * REDUCED MOTION is handled HERE, in JS, and not left to the global rule in
 * index.css. That rule forces `animation-iteration-count: 1` and a 0.01ms
 * duration, which snaps every vehicle to its FINAL keyframe — translateX(1420),
 * far off the right edge. The road would simply be empty. Parking each vehicle
 * at a fixed x keeps the scene composed and still.
 */
function Traffic({ reverse = false, duration, delay, restX, reduce, baseline, scale, bobDuration = 0.9, children }) {
  return (
    <g
      className={reduce ? undefined : reverse ? 'animate-ride-reverse' : 'animate-ride'}
      style={
        reduce
          ? { transform: `translateX(${restX}px)` }
          : { animationDuration: `${duration}s`, animationDelay: `${delay}s` }
      }
    >
      <g transform={`translate(0 ${baseline}) scale(${scale})`}>
        <g
          className={reduce ? undefined : 'animate-bob'}
          style={reduce ? undefined : { animationDelay: `${delay * 0.7}s`, animationDuration: `${bobDuration}s` }}
        >
          {children}
        </g>
      </g>
    </g>
  );
}

/** A delivery rider on an okada, facing right. Origin = tyres on tarmac. */
function Rider({ scale = 1, duration = 14, delay = 0, restX = 300, reduce }) {
  return (
    <Traffic baseline={344} scale={scale} duration={duration} delay={delay} restX={restX} reduce={reduce}>
      <ellipse cx="-2" cy="2" rx="36" ry="4.5" fill={C.ink} opacity="0.14" />

      {/* insulated delivery box */}
      <rect x="-38" y="-48" width="24" height="23" rx="3" fill={C.brand} />
      <rect x="-38" y="-48" width="24" height="6" rx="3" fill={C.brandDark} />
      <BoxMark x={-33} y={-42} size={15} />
      <path d="M-26 -25 v6" stroke={C.ink} strokeWidth="3" strokeLinecap="round" />

      {/* bike */}
      <path
        d="M-20 -9 L-12 -23 L4 -23 L15 -15 L20 -9"
        fill="none"
        stroke={C.ink}
        strokeWidth="3.4"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      <rect x="-17" y="-28" width="19" height="5.5" rx="2.7" fill={C.ink80} />
      <path d="M15 -15 L22 -19 L22 -13 Z" fill={C.amber} />
      <path d="M14 -17 L21 -31" stroke={C.ink} strokeWidth="2.8" strokeLinecap="round" />
      <circle cx="21.5" cy="-31.5" r="2.2" fill={C.ink80} />

      <Wheel cx={-20} cy={-9} reduce={reduce} />
      <Wheel cx={20} cy={-9} reduce={reduce} />

      {/* rider */}
      <path d="M-3 -27 L1 -16 L9 -13" fill="none" stroke={C.ink80} strokeWidth="3.8" strokeLinecap="round" strokeLinejoin="round" />
      <path d="M-3 -28 L7 -40" stroke={C.ink80} strokeWidth="7.5" strokeLinecap="round" />
      <path d="M-1 -31 L4 -37" stroke={C.amber} strokeWidth="3" strokeLinecap="round" />
      <path d="M5 -38 L19 -32" stroke={C.ink80} strokeWidth="3.2" strokeLinecap="round" />
      <circle cx="11" cy="-43" r="5.2" fill={C.skin} />
      <path d="M5.6 -43.4 a5.4 5.4 0 0 1 10.8 0 z" fill={C.brand} />
      <path d="M11 -48.8 a5.4 5.4 0 0 1 5.4 5.4 l3 0.6 l-3 1.4 z" fill={C.brandDark} />
    </Traffic>
  );
}

/** A keke napep — the yellow three-wheeler. Near lane, facing right. */
function Keke({ scale = 0.8, duration = 16, delay = 5, restX = 700, reduce }) {
  return (
    <Traffic baseline={344} scale={scale} duration={duration} delay={delay} restX={restX} reduce={reduce} bobDuration={1.2}>
      <ellipse cx="0" cy="2" rx="34" ry="4.5" fill={C.ink} opacity="0.14" />

      {/* cabin — rounded canopy over an open body */}
      <path
        d="M-30 -10 L-30 -34 Q-30 -50 -12 -52 L10 -52 Q26 -50 28 -34 L28 -10 Z"
        fill={C.amber}
      />
      {/* black skirt, like the danfo livery */}
      <rect x="-30" y="-22" width="58" height="6" fill={C.ink} />

      {/* windscreen + side opening */}
      <path d="M6 -48 Q22 -46 24 -33 L6 -33 Z" fill={C.glass} />
      <rect x="-24" y="-46" width="24" height="14" rx="2" fill={C.glass} opacity="0.6" />

      {/* passenger silhouette */}
      <circle cx="-8" cy="-40" r="4.4" fill={C.ink80} />
      <path d="M-8 -35 L-8 -26" stroke={C.ink80} strokeWidth="7" strokeLinecap="round" />

      {/* driver + handlebar */}
      <circle cx="14" cy="-42" r="4.2" fill={C.skin} />
      <path d="M14 -37 L14 -28" stroke={C.ink80} strokeWidth="6" strokeLinecap="round" />
      <path d="M16 -36 L24 -32" stroke={C.ink80} strokeWidth="2.8" strokeLinecap="round" />

      {/* headlight */}
      <circle cx="26" cy="-26" r="3" fill={C.white} />

      {/* one wheel at the front, two at the back — hence three-wheeler */}
      <Wheel cx={-22} cy={-9} r={9} reduce={reduce} />
      <Wheel cx={22} cy={-9} r={9} reduce={reduce} />
    </Traffic>
  );
}

/** A danfo — the yellow Lagos minibus. Far lane, right-to-left. */
function Danfo({ scale = 0.75, duration = 26, delay = 1, restX = 820, reduce }) {
  return (
    <Traffic
      baseline={300}
      scale={scale}
      duration={duration}
      delay={delay}
      restX={restX}
      reduce={reduce}
      reverse
      bobDuration={1.6}
    >
      <ellipse cx="0" cy="2" rx="64" ry="5" fill={C.ink} opacity="0.13" />

      <path d="M-62 -10 L-58 -40 Q-56 -46 -49 -46 L52 -46 Q58 -46 58 -40 L58 -10 Z" fill={C.amber} />
      <rect x="-61" y="-30" width="119" height="5" fill={C.ink} />
      <rect x="-61" y="-21" width="119" height="5" fill={C.ink} />

      <path d="M-56 -42 L-52 -33 L-36 -33 L-36 -42 Z" fill={C.glass} />
      {[-30, -10, 10, 30].map((wx) => (
        <rect key={wx} x={wx} y={-42} width="16" height="9" rx="1.5" fill={C.glass} />
      ))}

      <rect x="-30" y="-50" width="42" height="6" rx="2" fill={C.white} />
      <rect x="-27" y="-48.5" width="36" height="3" rx="1.5" fill={C.ink} opacity="0.55" />

      <rect x="-63" y="-18" width="4" height="5" rx="1.5" fill={C.white} />
      <rect x="56" y="-18" width="4" height="5" rx="1.5" fill={C.brand} />

      <Wheel cx={-38} cy={-9} r={10} reduce={reduce} />
      <Wheel cx={36} cy={-9} r={10} reduce={reduce} />
    </Traffic>
  );
}

/**
 * A parked food van.
 *
 * STATIC — no ride animation, no bob. It is parked, and a parked vehicle that
 * gently bobs looks broken rather than alive.
 *
 * Drawn BEFORE the near lane so the riders pass in FRONT of it. That single
 * ordering choice is what makes it read as parked on the far kerb instead of
 * abandoned in the middle of the road.
 */
function FoodVan({ x = 940, scale = 0.82 }) {
  return (
    <g transform={`translate(${x} 300) scale(${scale})`}>
      <ellipse cx="0" cy="2" rx="56" ry="5" fill={C.ink} opacity="0.13" />

      {/* body */}
      <path d="M-52 -10 L-52 -48 Q-52 -54 -45 -54 L30 -54 Q38 -54 42 -46 L52 -30 L52 -10 Z" fill={C.teal} />
      <rect x="-52" y="-24" width="104" height="6" fill={C.tealDark} />

      {/* cab window */}
      <path d="M32 -50 L40 -34 L52 -34 L44 -49 Z" fill={C.glass} />

      {/* serving hatch, propped open as an awning */}
      <rect x="-44" y="-46" width="56" height="22" rx="2" fill={C.white} opacity="0.92" />
      <rect x="-44" y="-46" width="56" height="6" rx="2" fill={C.tealDark} opacity="0.35" />
      <path d="M-48 -50 L16 -50 L22 -62 L-42 -62 Z" fill={C.brand} opacity="0.9" />
      {/* awning scallops */}
      {Array.from({ length: 6 }, (_, i) => -46 + i * 11).map((scallopX) => (
        <rect key={scallopX} x={scallopX} y={-52} width={5.5} height={4} fill={C.white} opacity="0.85" />
      ))}

      {/* counter + a pot on it */}
      <rect x="-46" y="-26" width="60" height="4" rx="1.5" fill={C.roof} />
      <rect x="-30" y="-36" width="16" height="10" rx="2" fill={C.kerbShade} />
      <ellipse cx="-22" cy="-36" rx="9" ry="2.6" fill={C.white} />

      {/* signboard on the flank */}
      <rect x="-18" y="-70" width="42" height="9" rx="2" fill={C.amber} />
      <rect x="-13" y="-67.5" width="26" height="4" rx="2" fill={C.ink} opacity="0.45" />

      {/* spin={false}: it is PARKED. Wheels turning on a stationary vehicle is
          the kind of detail nobody consciously notices and everybody feels. */}
      <Wheel cx={-32} cy={-9} r={9} spin={false} />
      <Wheel cx={30} cy={-9} r={9} spin={false} />
    </g>
  );
}

/* ==========================================================================
 * THE SCENE
 * ========================================================================== */

export default function StreetScene({ className = '' }) {
  const reduce = useReducedMotion();

  return (
    <svg
      viewBox="0 0 2000 420"
      // xMidYMax slice: scale to COVER the box, crop from the top, keep the
      // bottom edge pinned. The road and the verge are the subject and must
      // never be cut; the empty strip above the rooftops is expendable.
      // The caller sets the height — see HeroScene.jsx.
      preserveAspectRatio="xMidYMax slice"
      // Decoration only: never announced, never clickable.
      aria-hidden
      role="presentation"
      className={`pointer-events-none block w-full select-none ${className}`}
    >
      <defs>
        <linearGradient id="jr-road" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor={C.roadDark} />
          <stop offset="100%" stopColor={C.road} />
        </linearGradient>
      </defs>

      {/* ---------- distant skyline ---------- */}
      {/* Low under the headline (x < 1260), rising towards the right. */}
      <g fill={C.skyline} opacity="0.34">
        {[
          [20, 46], [76, 62], [132, 40], [188, 70], [244, 52],
          [300, 78], [356, 44], [412, 66], [468, 58], [524, 72],
          [580, 50], [636, 80], [692, 62], [748, 86], [804, 58],
          [860, 74], [916, 66], [972, 88], [1028, 60], [1084, 78], [1140, 68],
          [1196, 96], [1252, 120], [1308, 104], [1364, 138], [1420, 112],
          [1476, 146], [1532, 118], [1588, 152], [1644, 124], [1700, 144],
          [1756, 110], [1812, 150], [1868, 122], [1924, 140], [1980, 106],
        ].map(([bx, bh]) => (
          <rect key={bx} x={bx} y={GROUND - bh} width={46} height={bh} rx="2" />
        ))}
      </g>

      {/* ---------- LOW ZONE (x 0–1260): the headline sits over this -------- */}
      <Palm x={40} height={104} />
      <Shop x={84} w={120} h={86} wall={C.wallA} awning={C.brand} dish />
      <Shop x={214} w={98} h={72} wall={C.wallB} awning={C.amber} />

      {/* The smallest blocks drop out on phones — at 375px the scene renders
          ~180px tall and this level of detail turns to mud. */}
      <g className="hidden sm:block">
        <Shop x={322} w={88} h={80} wall={C.wallC} awning={C.palmLeaf} />
        <Palm x={428} height={88} flip />
      </g>

      <Shop x={462} w={112} h={92} wall={C.wallB} awning={C.brand} tank />
      <Shop x={584} w={96} h={74} wall={C.wallA} awning={C.amber} dish />

      <g className="hidden sm:block">
        <Palm x={700} height={96} />
      </g>
      <Shop x={730} w={104} h={84} wall={C.wallC} awning={C.brand} />
      <Shop x={850} w={110} h={78} wall={C.wallA} awning={C.amber} dish />

      <g className="hidden sm:block">
        <Shop x={972} w={92} h={88} wall={C.wallB} awning={C.palmLeaf} tank />
      </g>

      <Shop x={1080} w={106} h={82} wall={C.wallC} awning={C.amber} />
      <g className="hidden sm:block">
        <Palm x={1206} height={94} flip />
      </g>

      {/* ---------- TALL ZONE (x 1280+): no copy overlaps here -------------- */}
      <AnchorBuilding x={1280} w={230} h={200} />

      <Shop x={1530} w={110} h={104} wall={C.wallA} awning={C.brand} storeys={2} tank />
      <Palm x={1655} height={100} />
      <Shop x={1690} w={118} h={112} wall={C.wallB} awning={C.palmLeaf} storeys={2} dish />
      <Shop x={1826} w={104} h={88} wall={C.wallC} awning={C.amber} />
      <Shop x={1946} w={104} h={96} wall={C.wallA} awning={C.brand} storeys={2} />

      {/* ---------- road ---------- */}
      <rect x="0" y="243" width="2000" height="17" fill={C.kerb} />
      <rect x="0" y="243" width="2000" height="4" fill={C.kerbShade} />
      <rect x="0" y="260" width="2000" height="102" fill="url(#jr-road)" />
      <path d="M0 318 H2000" stroke={C.dash} strokeWidth="3" strokeDasharray="30 26" opacity="0.8" />

      {/* ---------- far lane ---------- */}
      {/* Parked van first, then the danfo, then the near lane. Draw order IS
          depth order here, and it is what puts the riders in FRONT of the van
          so it reads as parked on the far kerb rather than stalled in traffic. */}
      <FoodVan x={1600} scale={0.82} />
      <Danfo scale={0.75} duration={26} delay={1} restX={900} reduce={reduce} />

      {/* ---------- near lane ---------- */}
      {/* Four different durations so nothing ever falls into step — synchronised
          loops are what make an animation read as cheap. */}
      <Rider scale={0.85} duration={14} delay={0} restX={300} reduce={reduce} />
      <Keke scale={0.8} duration={16} delay={5} restX={800} reduce={reduce} />
      <Rider scale={1.0} duration={19} delay={3.5} restX={1300} reduce={reduce} />
      <Rider scale={0.9} duration={11} delay={7} restX={1750} reduce={reduce} />

      {/* ---------- foreground ---------- */}
      <rect x="0" y="362" width="2000" height="12" fill={C.kerb} />
      <rect x="0" y="362" width="2000" height="3" fill={C.kerbShade} />
      <rect x="0" y="374" width="2000" height="46" fill={C.grass} />
      <path
        d="M0 374 Q80 382 160 375 T320 376 T480 374 T640 377 T800 374 T960 376 T1120 374 T1280 377 T1440 374 T1600 376 T1760 374 T1920 377 T2000 375 L2000 420 L0 420 Z"
        fill={C.grassDark}
        opacity="0.55"
      />
    </svg>
  );
}
