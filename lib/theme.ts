import type {CSSProperties} from 'react';
export const neonPalettes:Record<string,[string,string,string,string]>={
 black:['Black Gold','#f4cb6b','#10141e','#090c13'],
 ocean:['Ocean Blue','#4cddff','#0a1929','#060e19'],
 emerald:['Emerald','#55efaf','#0a201a','#060f0d'],
 red:['Urban Red','#ff718b','#24101c','#12090f'],
 classic:['Classic Barber','#ffbb85','#251911','#140e0a'],
};
export function readableText(color:string){if(!/^#[0-9a-f]{6}$/i.test(color))return '#10141e';const a=[1,3,5].map(i=>parseInt(color.slice(i,i+2),16)/255).map(v=>v<=.04045?v/12.92:((v+.055)/1.055)**2.4);return a[0]*.2126+a[1]*.7152+a[2]*.0722>.179?'#0a1018':'#fff';}
export function neonTheme(palette='black',custom?:string):CSSProperties{const p=neonPalettes[palette]||neonPalettes.black;const accent=custom&&/^#[0-9a-f]{6}$/i.test(custom)?custom:p[1];return {'--accent':accent,'--ink':p[2],'--paper':p[3],'--buttontext':readableText(accent)} as CSSProperties;}
