import type { Metadata } from 'next';
import '../styles.css';

export const metadata: Metadata = {
  title: '云长卫｜拖给二爷，自动收好',
  description: '原生 macOS 文件收纳工具。把文件拖给二爷，自动分类、重复检测，收错还能一键撤回。',
  icons: { icon: '/assets/favicon.png' },
  openGraph: {
    title: '云长卫｜拖给二爷，自动收好',
    description: '原生 macOS 文件收纳工具。自动分类、重复检测，收错还能一键撤回。',
    siteName: '云长卫',
    type: 'website',
    images: [{ url: '/og.jpg', width: 1792, height: 1024, alt: '云长卫｜拖给二爷，自动收好' }],
  },
  twitter: {
    card: 'summary_large_image',
    title: '云长卫｜拖给二爷，自动收好',
    description: '原生 macOS 文件收纳工具。自动分类、重复检测，收错还能一键撤回。',
    images: ['/og.jpg'],
  },
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="zh-CN">
      <body>
        {children}
        <script defer src="https://cdn.jsdelivr.net/npm/gsap@3.12.5/dist/gsap.min.js" />
        <script defer src="https://cdn.jsdelivr.net/npm/gsap@3.12.5/dist/ScrollTrigger.min.js" />
        <script defer src="/site.js" />
      </body>
    </html>
  );
}
