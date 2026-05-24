import { useState } from "react";
import { Providers } from "@/app/providers";
import { AppRoutes } from "@/app/routes";
import { ConnectGate } from "@/features/connect/ConnectGate";
import { getStoredApiKey } from "@/features/onboarding/api";

const App = () => {
  // The app is gated on a verified API key. A key persisted earlier this
  // browser session lets the user straight through (survives reloads).
  const [connected, setConnected] = useState(() => getStoredApiKey() !== null);

  return (
    <Providers>
      {connected ? <AppRoutes /> : <ConnectGate onConnected={() => setConnected(true)} />}
    </Providers>
  );
};

export default App;
