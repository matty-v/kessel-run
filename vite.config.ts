import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// Deployed to GitHub Pages under /kessel-run/ (the working repo's name, not the template's)
export default defineConfig({
  base: '/kessel-run/',
  plugins: [react()],
})
