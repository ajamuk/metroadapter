/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,jsx}'],
  theme: {
    extend: {
      colors: {
        amber: { DEFAULT: '#f59e0b', 400: '#fbbf24', 500: '#f59e0b', 600: '#d97706' },
      },
      fontFamily: {
        bebas: ['"Bebas Neue"', 'sans-serif'],
        mono: ['"JetBrains Mono"', 'monospace'],
        sans: ['"DM Sans"', 'sans-serif'],
      },
      borderRadius: { DEFAULT: '4px', sm: '2px', md: '4px', lg: '4px', xl: '4px', '2xl': '4px' },
    },
  },
  plugins: [],
}
