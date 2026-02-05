.PHONY: server console help

server:
	@echo "🚀 Starting Phoenix server with remote console support..."
	@echo "📝 Server: http://localhost:4000"
	@echo "🔧 Remote console: make console"
	@iex --sname phoenix@localhost -S mix phx.server

console:
	@echo "🔌 Connecting to remote Phoenix console..."
	@echo "💡 Commands: recompile() | System.restart() | Ctrl+C twice to exit"
	@iex --sname console@localhost --remsh phoenix@localhost

help:
	@echo "Phoenix Template Server - Available Commands"
	@echo ""
	@echo "Development:"
	@echo "  make server            - Start Phoenix server with remote console"
	@echo "  make console           - Connect to running Phoenix console"
	@echo ""
	@echo "Usage:"
	@echo "  1. Start server:  make server"
	@echo "  2. In another terminal, connect: make console"
	@echo "  3. In console, try: recompile() or System.restart()"
