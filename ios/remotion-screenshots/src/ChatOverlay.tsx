import React from "react";

// Fake chat content overlaid on top of the real chat capture so the
// marketing screenshot shows a believable, fully populated group chat
// instead of the sparse dev-account conversation.

type Message = {
  from: "me" | "them";
  text: string;
  sender?: string;
  avatarColor?: string;
  initials?: string;
};

const MESSAGES: Message[] = [
  {
    from: "me",
    text: "Court's locked in for tomorrow night",
  },
  {
    from: "them",
    sender: "Marcus",
    text: "Im in, bringing my brother",
    avatarColor: "#7C3AED",
    initials: "M",
  },
  {
    from: "me",
    text: "3 spots left, first come first served",
  },
  {
    from: "them",
    sender: "Chris",
    text: "Locked in",
    avatarColor: "#059669",
    initials: "C",
  },
  {
    from: "them",
    sender: "Chance",
    text: "Who else running tomorrow?",
    avatarColor: "#DC2626",
    initials: "CH",
  },
  {
    from: "me",
    text: "Full roster going. See you at 10",
  },
];

const ME_BUBBLE = "#F97316"; // brand orange
const THEM_BUBBLE = "#1C1C1E";
const ME_AVATAR = "#7C2D12";
const BG = "#0A0A0A";

export const ChatOverlay: React.FC<{ scale: number }> = ({ scale }) => {
  const s = scale;

  return (
    <div
      style={{
        position: "absolute",
        // leave the captured chrome visible: status bar + "Chat" nav above,
        // message input + tab bar below
        top: "11.5%",
        bottom: "16.5%",
        left: 0,
        right: 0,
        background: BG,
        padding: `${60 * s}px ${36 * s}px ${20 * s}px ${36 * s}px`,
        display: "flex",
        flexDirection: "column",
        justifyContent: "flex-end",
        gap: 34 * s,
      }}
    >
      {MESSAGES.map((msg, i) => (
        <ChatBubble key={i} msg={msg} scale={s} />
      ))}
    </div>
  );
};

const ChatBubble: React.FC<{ msg: Message; scale: number }> = ({
  msg,
  scale,
}) => {
  const isMe = msg.from === "me";
  const s = scale;

  const avatarSize = 52 * s;
  const bubblePadY = 26 * s;
  const bubblePadX = 42 * s;
  const fontSize = 44 * s;
  const nameFontSize = 28 * s;

  const avatar = (
    <div
      style={{
        width: avatarSize,
        height: avatarSize,
        borderRadius: "50%",
        background: isMe ? ME_AVATAR : (msg.avatarColor ?? "#374151"),
        flexShrink: 0,
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        color: "#FFFFFF",
        fontSize: 22 * s,
        fontWeight: 700,
      }}
    >
      {isMe ? "IP" : (msg.initials ?? "?")}
    </div>
  );

  const bubble = (
    <div
      style={{
        maxWidth: "72%",
        background: isMe ? ME_BUBBLE : THEM_BUBBLE,
        color: "#FFFFFF",
        fontSize,
        fontWeight: 500,
        padding: `${bubblePadY}px ${bubblePadX}px`,
        borderRadius: 44 * s,
        lineHeight: 1.22,
      }}
    >
      {msg.text}
    </div>
  );

  return (
    <div
      style={{
        display: "flex",
        flexDirection: "column",
        alignItems: isMe ? "flex-end" : "flex-start",
      }}
    >
      {!isMe && msg.sender && (
        <div
          style={{
            color: "#FB923C",
            fontSize: nameFontSize,
            fontWeight: 600,
            marginBottom: 10 * s,
            marginLeft: avatarSize + 18 * s,
          }}
        >
          {msg.sender}
        </div>
      )}
      <div
        style={{
          display: "flex",
          alignItems: "flex-end",
          gap: 14 * s,
          flexDirection: isMe ? "row-reverse" : "row",
        }}
      >
        {avatar}
        {bubble}
      </div>
    </div>
  );
};
