import { AbsoluteFill, Img, staticFile, useVideoConfig } from "remotion";
import { ChatOverlay } from "./ChatOverlay";

export type ScreenshotProps = {
  capture: string;
  headline: string;
  subhead: string;
  overlayType?: "chat" | null;
};

// Brand accent from RunsByIP-iOS/Assets.xcassets/AccentColor.colorset
// rgb(249, 115, 22) = #F97316
const ORANGE = "#F97316";
const ORANGE_LIGHT = "#FB923C";
const BG_DARK = "#0A0A0A";

const FONT_STACK =
  '-apple-system, "SF Pro Display", "Helvetica Neue", Helvetica, Arial, sans-serif';

export const Screenshot: React.FC<ScreenshotProps> = ({
  capture,
  headline,
  subhead,
  overlayType,
}) => {
  const { width, height } = useVideoConfig();

  // Scale fonts & spacing proportionally to canvas width so 6.9" and 6.5"
  // both look right with the same component.
  const scale = width / 1290;
  const headlineSize = Math.round(118 * scale);
  const subheadSize = Math.round(54 * scale);
  const headlineTop = Math.round(180 * scale);
  const subheadTop = Math.round(headlineTop + headlineSize * 1.25);

  // Phone frame
  const frameWidth = Math.round(width * 0.82);
  const frameHeight = Math.round((frameWidth * 2796) / 1290); // iPhone 16 Pro aspect
  const frameTop = Math.round(height * 0.3);
  const frameBorder = Math.round(16 * scale);
  const frameRadius = Math.round(90 * scale);

  return (
    <AbsoluteFill
      style={{
        fontFamily: FONT_STACK,
        background: BG_DARK,
      }}
    >
      {/* Radial glow behind headline */}
      <AbsoluteFill
        style={{
          background: `radial-gradient(ellipse 80% 50% at 50% 18%, ${ORANGE}55 0%, ${ORANGE}00 60%), linear-gradient(180deg, #141414 0%, #070707 100%)`,
        }}
      />

      {/* Headline + subhead */}
      <div
        style={{
          position: "absolute",
          top: headlineTop,
          left: 0,
          right: 0,
          textAlign: "center",
          padding: `0 ${Math.round(80 * scale)}px`,
        }}
      >
        <div
          style={{
            color: "#FFFFFF",
            fontSize: headlineSize,
            fontWeight: 800,
            letterSpacing: -2 * scale,
            lineHeight: 1.02,
          }}
        >
          {headline}
        </div>
        <div
          style={{
            position: "absolute",
            top: subheadTop - headlineTop,
            left: 0,
            right: 0,
            color: ORANGE_LIGHT,
            fontSize: subheadSize,
            fontWeight: 500,
            letterSpacing: -0.5,
          }}
        >
          {subhead}
        </div>
      </div>

      {/* Phone frame */}
      <div
        style={{
          position: "absolute",
          top: frameTop,
          left: (width - frameWidth) / 2,
          width: frameWidth,
          height: frameHeight,
          borderRadius: frameRadius,
          background: "#1A1A1A",
          padding: frameBorder,
          boxShadow: `0 ${40 * scale}px ${120 * scale}px rgba(0,0,0,0.6), 0 0 0 ${Math.round(2 * scale)}px #2A2A2A`,
        }}
      >
        <div
          style={{
            width: "100%",
            height: "100%",
            borderRadius: frameRadius - frameBorder,
            overflow: "hidden",
            background: "#000",
            position: "relative",
          }}
        >
          <Img
            src={staticFile(capture)}
            style={{
              width: "100%",
              height: "100%",
              objectFit: "cover",
              display: "block",
            }}
          />
          {overlayType === "chat" && <ChatOverlay scale={scale} />}
        </div>
      </div>
    </AbsoluteFill>
  );
};
