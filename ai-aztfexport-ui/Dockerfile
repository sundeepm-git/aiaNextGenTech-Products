# =============================================
# Next.js UI Dockerfile
# =============================================

# Stage 1: Build
FROM node:18-alpine AS builder
WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY . .

# These are baked into the JS bundle at build time.
# The deploy script passes actual Container App URLs via --build-arg.
ARG NEXT_PUBLIC_MCP_SERVER_URL
ARG NEXT_PUBLIC_WORKFLOW_API_URL
ENV NEXT_PUBLIC_MCP_SERVER_URL=$NEXT_PUBLIC_MCP_SERVER_URL
ENV NEXT_PUBLIC_WORKFLOW_API_URL=$NEXT_PUBLIC_WORKFLOW_API_URL

RUN npm run build

# Stage 2: Production
FROM node:18-alpine AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV PORT=3000
ENV HOSTNAME=0.0.0.0

# Copy standalone output
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static

EXPOSE 3000

CMD ["node", "server.js"]
