import { createContext, useContext } from 'react'

export const NodeEditContext = createContext<((id: string) => void) | null>(null)

export const useOpenNode = () => useContext(NodeEditContext)
