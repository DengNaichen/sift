import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import App from './App'
import { MockMailAdapter } from './adapter/mockMailAdapter'
import './index.css'

// 换成 Apple Mail 本机桥接时，只需替换这一行。
const adapter = new MockMailAdapter()

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App adapter={adapter} />
  </StrictMode>,
)
