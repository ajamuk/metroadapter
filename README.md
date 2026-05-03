# Metro WOD Adapter

CrossFit Metropolitano — WOD adaptation tool powered by Claude AI.

## Setup

```bash
# 1. Clone the repo
git clone <repo-url>
cd metroadapter

# 2. Install dependencies
npm install

# 3. Configure your API key
cp .env.example .env
# Edit .env and add your Anthropic API key

# 4. Start the dev server
npm run dev
```

Open [http://localhost:5173](http://localhost:5173) in your browser.

## Configuration

Create a `.env` file at the root:

```
VITE_ANTHROPIC_API_KEY=your_key_here
```

Get your API key at [console.anthropic.com](https://console.anthropic.com).
