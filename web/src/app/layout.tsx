import type { Metadata, Viewport } from "next";
import "./globals.css";
import { ExperiencePreferencesSync } from "@/components/ExperiencePreferencesSync";
import { PWARegister } from "@/components/PWARegister";
import { ReminderNotifier } from "@/components/ReminderNotifier";
import { FottyShell } from "@/components/FottyShell";
import { getSiteUrl } from "@/lib/fotty-config";

export const metadata: Metadata = {
  metadataBase: new URL(getSiteUrl()),
  title: "FOTTY | Live Sports, Match Day, and Channels",
  description: "Browse live sports, follow match day fixtures, and install Fotty for a fast app-like viewing experience.",
  manifest: "/manifest.json",
  appleWebApp: {
    capable: true,
    statusBarStyle: "black-translucent",
    title: "FOTTY",
  },
  formatDetection: {
    telephone: false,
  },
};

export const viewport: Viewport = {
  themeColor: "#0A0D14",
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className="dark" suppressHydrationWarning>
      <head>
        <link rel="icon" href="/favicon.ico" />
        <link rel="apple-touch-icon" href="/icon-192.png" />
        <meta name="apple-mobile-web-app-capable" content="yes" />
        <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent" />
        <meta name="mobile-web-app-capable" content="yes" />
      </head>
      <body className="antialiased select-none touch-pan-y" suppressHydrationWarning>
        <ExperiencePreferencesSync />
        <PWARegister />
        <ReminderNotifier />
        <FottyShell bare={false}>{children}</FottyShell>
      </body>
    </html>
  );
}
