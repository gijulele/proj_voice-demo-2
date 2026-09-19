import path from "node:path";
import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // 저장소 루트에도 package-lock.json 이 있어서(= supabase/ 검증 스크립트용)
  // Next.js 가 워크스페이스 루트를 그쪽으로 잘못 추론하고 경고를 띄운다.
  // 이 앱의 루트는 여기(app/)라고 명시해 둔다.
  turbopack: {
    root: path.resolve(__dirname),
  },
};

export default nextConfig;
