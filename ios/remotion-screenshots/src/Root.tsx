import { Composition } from "remotion";
import { Screenshot, ScreenshotProps } from "./Screenshot";

// App Store screenshot sizes
const SIZE_69 = { width: 1290, height: 2796 }; // iPhone 6.9"
const SIZE_65 = { width: 1242, height: 2688 }; // iPhone 6.5"

type Screen = {
  slug: "sessions-list" | "session-detail" | "chat";
  capture: string;
  headline: string;
  subhead: string;
  overlayType?: "chat" | null;
};

const SCREENS: Screen[] = [
  {
    slug: "sessions-list",
    capture: "captures/sessions-list.png",
    headline: "Never miss a run",
    subhead: "See every upcoming run at a glance",
  },
  {
    slug: "session-detail",
    capture: "captures/session-detail.png",
    headline: "Tap to RSVP",
    subhead: "Know who's showing up before you get there",
  },
  {
    slug: "chat",
    capture: "captures/chat.png",
    headline: "Stay in the loop",
    subhead: "Chat with your crew between runs",
    overlayType: "chat",
  },
];

export const RemotionRoot: React.FC = () => {
  return (
    <>
      {SCREENS.map((screen) => {
        const propsBase: ScreenshotProps = {
          capture: screen.capture,
          headline: screen.headline,
          subhead: screen.subhead,
          overlayType: screen.overlayType ?? null,
        };
        return (
          <>
            <Composition
              key={`${screen.slug}-69`}
              id={`${screen.slug}-69`}
              component={Screenshot}
              durationInFrames={1}
              fps={30}
              width={SIZE_69.width}
              height={SIZE_69.height}
              defaultProps={propsBase}
            />
            <Composition
              key={`${screen.slug}-65`}
              id={`${screen.slug}-65`}
              component={Screenshot}
              durationInFrames={1}
              fps={30}
              width={SIZE_65.width}
              height={SIZE_65.height}
              defaultProps={propsBase}
            />
          </>
        );
      })}
    </>
  );
};
