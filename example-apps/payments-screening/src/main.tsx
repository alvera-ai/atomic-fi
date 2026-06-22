import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { Toaster } from 'sonner'
import './index.css'
import App from './App.tsx'
import { ConfigProvider } from './components/ConfigProvider'

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <ConfigProvider>
      <App />
      <Toaster
        theme="dark"
        position="bottom-right"
        toastOptions={{
          style: {
            background: 'oklch(0.236 0.009 165)',
            border: '1px solid oklch(0.3 0.01 165)',
            color: 'oklch(0.965 0.005 150)',
          },
        }}
      />
    </ConfigProvider>
  </StrictMode>,
)
