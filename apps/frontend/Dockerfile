# Frontend Dockerfile — nginx serving static HTML.
# No build stage needed: just copy the static files into the nginx image.
# Final image is ~25 MB.
FROM nginx:1.25-alpine

# Replace the default nginx config with ours.
# The default config serves /usr/share/nginx/html on port 80, but lacks /health.
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copy the static site content
COPY index.html /usr/share/nginx/html/index.html

EXPOSE 80

# nginx starts in daemon mode by default — "daemon off" keeps it in the foreground
# so Docker can track the process and restart the container if it crashes.
CMD ["nginx", "-g", "daemon off;"]
