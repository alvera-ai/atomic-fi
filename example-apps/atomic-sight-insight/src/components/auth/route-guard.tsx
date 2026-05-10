import { Navigate, Outlet, useLocation } from "react-router-dom";
import { useAuth } from "@/contexts/auth-context";
import { canAccessRoute, ROLE_DEFAULT_ROUTE } from "@/lib/nav-access";

export function RouteGuard() {
  const { user } = useAuth();
  const { pathname } = useLocation();
  if (!canAccessRoute(user.role, pathname)) {
    return <Navigate to={ROLE_DEFAULT_ROUTE[user.role]} replace />;
  }
  return <Outlet />;
}
