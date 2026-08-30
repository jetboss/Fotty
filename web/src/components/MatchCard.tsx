import React from 'react';
import { Play, Users, TrendingUp } from 'lucide-react';

interface MatchCardProps {
  homeTeam: { name: string; logo: string; score?: number };
  awayTeam: { name: string; logo: string; score?: number };
  league: string;
  time: string;
  isLive?: boolean;
  viewerCount?: string;
  onClick?: () => void;
}

export const MatchCard: React.FC<MatchCardProps> = ({
  homeTeam,
  awayTeam,
  league,
  time,
  isLive,
  viewerCount,
  onClick
}) => {
  return (
    <div 
      onClick={onClick}
      className="card-style group relative overflow-hidden transition-all duration-300 hover:scale-[1.02] active:scale-[0.98] cursor-pointer"
    >
      {/* League Header */}
      <div className="flex items-center justify-between px-md py-sm bg-white/5 border-b border-white/5">
        <span className="text-[10px] font-bold tracking-widest text-text-tertiary uppercase">
          {league}
        </span>
        {isLive && (
          <div className="flex items-center gap-1.5">
            <div className="w-1.5 h-1.5 rounded-full bg-live animate-pulse" />
            <span className="text-[10px] font-black text-live uppercase tracking-tighter">
              LIVE
            </span>
          </div>
        )}
      </div>

      {/* Teams Container */}
      <div className="p-md space-y-md">
        <div className="flex items-center justify-between">
          <div className="flex flex-col items-center gap-2 flex-1">
            <div className="w-14 h-14 premium-glass flex items-center justify-center p-2.5 overflow-hidden">
              {homeTeam.logo.length <= 4 ? (
                <span className="text-xs font-black italic text-accent">{homeTeam.logo}</span>
              ) : (
                <img src={homeTeam.logo} alt={homeTeam.name} className="w-full h-full object-contain" />
              )}
            </div>
            <span className="text-[11px] font-black tracking-tight text-center line-clamp-1">{homeTeam.name}</span>
          </div>

          <div className="flex flex-col items-center gap-1 px-2">
            {isLive ? (
              <div className="flex items-center gap-3">
                <span className="text-3xl font-black italic tracking-tighter">{homeTeam.score ?? 0}</span>
                <span className="text-text-tertiary font-bold">:</span>
                <span className="text-3xl font-black italic tracking-tighter">{awayTeam.score ?? 0}</span>
              </div>
            ) : (
              <div className="px-3 py-1.5 rounded-full bg-white/5 border border-white/10">
                <span className="text-[10px] font-black text-text-secondary tracking-widest">{time}</span>
              </div>
            )}
          </div>

          <div className="flex flex-col items-center gap-2 flex-1">
            <div className="w-14 h-14 premium-glass flex items-center justify-center p-2.5 overflow-hidden">
              {awayTeam.logo.length <= 4 ? (
                <span className="text-xs font-black italic text-accent">{awayTeam.logo}</span>
              ) : (
                <img src={awayTeam.logo} alt={awayTeam.name} className="w-full h-full object-contain" />
              )}
            </div>
            <span className="text-[11px] font-black tracking-tight text-center line-clamp-1">{awayTeam.name}</span>
          </div>
        </div>

        {/* Footer Stats */}
        <div className="flex items-center justify-between pt-sm border-t border-white/5">
          <div className="flex items-center gap-3">
            <div className="flex items-center gap-1 text-text-tertiary">
              <Users size={12} />
              <span className="text-[10px] font-bold">{viewerCount ?? '2.4k'}</span>
            </div>
            <div className="flex items-center gap-1 text-text-tertiary">
              <TrendingUp size={12} />
              <span className="text-[10px] font-bold">Hot</span>
            </div>
          </div>
          
          <button className="flex items-center gap-1.5 px-3 py-1 rounded-full accent-gradient premium-shadow">
            <Play size={10} fill="white" />
            <span className="text-[10px] font-black uppercase italic">Watch</span>
          </button>
        </div>
      </div>
    </div>
  );
};
