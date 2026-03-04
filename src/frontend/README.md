# ACC v3 -- Frontend

Vue 3 + TypeScript + Vite dashboard.

The frontend will be migrated from ACC v2 in a future phase.
For now, the backend API is fully functional and can be tested via curl or the WebSocket.

## API Endpoints

- `GET  /health` -- Service health
- `GET  /api/projects` -- List projects
- `GET  /api/sessions?project_id=` -- List sessions
- `POST /api/agent-update` -- Log agent event
- `POST /api/stats-update` -- Log performance metric
- `POST /api/chat-message` -- Store chat message
- `POST /api/memories` -- Store agent memory (auto-embeds)
- `POST /api/memories/search` -- Semantic search memories
- `GET  /api/dashboard/performance?project_id=&days=7` -- Performance aggregate
- `GET  /api/dashboard/activity?project_id=&hours=24` -- Activity aggregate
