import { ShimmerBlock } from "@/components/Skeleton";

export default function Loading() {
  return (
    <div className="min-h-dvh bg-background">
      <div className="mx-auto max-w-6xl space-y-4 px-md py-6">
        <ShimmerBlock className="h-5 w-40" />
        <ShimmerBlock className="aspect-video w-full rounded-2xl" />
        <div className="grid gap-3 sm:grid-cols-2">
          <ShimmerBlock className="h-20 w-full rounded-xl" />
          <ShimmerBlock className="h-20 w-full rounded-xl" />
        </div>
      </div>
    </div>
  );
}
