export function json(body: unknown, status: number) {
  return Response.json(body, { status });
}
