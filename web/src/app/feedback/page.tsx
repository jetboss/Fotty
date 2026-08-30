"use client";

import Link from "next/link";
import React, { useEffect, useMemo, useState } from "react";
import { ArrowLeft, Copy, Mail, Send } from "lucide-react";

const FEEDBACK_DRAFT_KEY = "fotty.web.feedbackDraft";
const supportEmail = process.env.NEXT_PUBLIC_SUPPORT_EMAIL;

const categories = [
  "Bug",
  "Slow or buffering",
  "Install or PWA",
  "Reminder flow",
  "UX idea",
  "Other",
];

export default function FeedbackPage() {
  const [draft] = useState(() => {
    if (typeof window === "undefined") return { category: categories[0], message: "" };

    try {
      const saved = window.localStorage.getItem(FEEDBACK_DRAFT_KEY);
      if (!saved) return { category: categories[0], message: "" };
      const parsed = JSON.parse(saved) as { category?: string; message?: string };
      return {
        category: parsed.category && categories.includes(parsed.category) ? parsed.category : categories[0],
        message: parsed.message || "",
      };
    } catch {
      return { category: categories[0], message: "" };
    }
  });
  const [category, setCategory] = useState(draft.category);
  const [message, setMessage] = useState(draft.message);
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    try {
      window.localStorage.setItem(FEEDBACK_DRAFT_KEY, JSON.stringify({ category, message }));
    } catch {
      // Ignore local draft failures.
    }
  }, [category, message]);

  const composedBody = useMemo(() => {
    const lines = [
      `Category: ${category}`,
      "",
      message.trim() || "Share what felt broken, slow, or missing.",
      "",
      `Page: ${typeof window !== "undefined" ? window.location.href : "Feedback"}`,
    ];

    return lines.join("\n");
  }, [category, message]);

  const mailtoHref = supportEmail
    ? `mailto:${supportEmail}?subject=${encodeURIComponent(`Fotty feedback: ${category}`)}&body=${encodeURIComponent(composedBody)}`
    : undefined;

  return (
    <main className="min-h-screen bg-background pb-32 pt-12 text-text-primary">
      <header className="space-y-4 px-md">
        <Link
          href="/settings"
          className="inline-flex h-10 w-10 items-center justify-center rounded-full bg-surface text-text-primary"
          aria-label="Back to settings"
        >
          <ArrowLeft size={18} />
        </Link>

        <div className="space-y-2">
          <h1 className="text-4xl font-black">Feedback</h1>
          <p className="max-w-2xl text-sm font-medium leading-6 text-text-secondary">
            Share what feels broken, slow, confusing, or still missing. Fotty will keep your draft on this device while you write.
          </p>
        </div>
      </header>

      <div className="space-y-4 px-md py-lg">
        <section className="rounded-xl border border-white/5 bg-surface p-4">
          <div className="space-y-4">
            <div className="space-y-2">
              <p className="text-xs font-bold uppercase text-text-tertiary">Category</p>
              <div className="flex flex-wrap gap-2">
                {categories.map((option) => (
                  <button
                    key={option}
                    type="button"
                    onClick={() => setCategory(option)}
                    className={option === category
                      ? "rounded-full bg-accent px-4 py-2 text-xs font-bold text-white"
                      : "rounded-full border border-white/10 bg-white/5 px-4 py-2 text-xs font-bold text-text-secondary"}
                  >
                    {option}
                  </button>
                ))}
              </div>
            </div>

            <div className="space-y-2">
              <label htmlFor="feedback-message" className="text-xs font-bold uppercase text-text-tertiary">
                What happened
              </label>
              <textarea
                id="feedback-message"
                value={message}
                onChange={(event) => setMessage(event.target.value)}
                placeholder="What were you trying to do, and what felt off?"
                className="min-h-40 w-full rounded-xl border border-white/10 bg-background px-4 py-3 text-sm text-text-primary outline-none placeholder:text-text-tertiary"
              />
            </div>

            <div className="flex flex-wrap gap-2">
              {mailtoHref && (
                <a
                  href={mailtoHref}
                  className="inline-flex items-center gap-2 rounded-full accent-gradient px-4 py-2 text-xs font-bold text-white"
                >
                  <Send size={14} />
                  Send email
                </a>
              )}
              <button
                type="button"
                onClick={async () => {
                  try {
                    await navigator.clipboard.writeText(composedBody);
                    setCopied(true);
                    window.setTimeout(() => setCopied(false), 2000);
                  } catch {
                    setCopied(false);
                  }
                }}
                className="inline-flex items-center gap-2 rounded-full border border-white/10 bg-white/5 px-4 py-2 text-xs font-bold text-text-primary"
              >
                <Copy size={14} />
                {copied ? "Copied" : "Copy summary"}
              </button>
              {!mailtoHref && (
                <div className="inline-flex items-center gap-2 rounded-full border border-white/10 px-4 py-2 text-xs font-bold text-text-secondary">
                  <Mail size={14} />
                  Inbox not configured yet
                </div>
              )}
            </div>
          </div>
        </section>
      </div>
    </main>
  );
}
