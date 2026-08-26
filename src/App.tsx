import { Button } from "@/components/ui/button"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Textarea } from "@/components/ui/textarea"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Badge } from "@/components/ui/badge"

function App() {
  return (
    <div className="min-h-screen bg-background p-8 space-y-6">
      <h1 className="text-2xl font-semibold">SaaS Panel Design System</h1>

      <div className="space-y-4">
        <h2 className="text-lg font-medium">Buttons</h2>
        <div className="flex flex-wrap gap-2">
          <Button>Default</Button>
          <Button variant="destructive">Destructive</Button>
          <Button variant="outline">Outline</Button>
          <Button variant="secondary">Secondary</Button>
          <Button variant="ghost">Ghost</Button>
          <Button variant="link">Link</Button>
        </div>
      </div>

      <div className="space-y-4">
        <h2 className="text-lg font-medium">Card</h2>
        <Card className="max-w-md">
          <CardHeader>
            <CardTitle>Card Title</CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-sm text-muted-foreground">
              Card content with soft border and rounded corners.
            </p>
          </CardContent>
        </Card>
      </div>

      <div className="space-y-4">
        <h2 className="text-lg font-medium">Form Inputs</h2>
        <div className="max-w-md space-y-2">
          <Input placeholder="Input (h-9, focus ring)" />
          <Textarea placeholder="Textarea with focus ring" />
        </div>
      </div>

      <div className="space-y-4">
        <h2 className="text-lg font-medium">Table</h2>
        <Table className="max-w-lg">
          <TableHeader>
            <TableRow>
              <TableHead>Name</TableHead>
              <TableHead>Status</TableHead>
              <TableHead>Value</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            <TableRow>
              <TableCell>Item A</TableCell>
              <TableCell><Badge>Active</Badge></TableCell>
              <TableCell>1,234</TableCell>
            </TableRow>
            <TableRow>
              <TableCell>Item B</TableCell>
              <TableCell><Badge variant="secondary">Inactive</Badge></TableCell>
              <TableCell>—</TableCell>
            </TableRow>
          </TableBody>
        </Table>
      </div>
    </div>
  )
}

export default App
