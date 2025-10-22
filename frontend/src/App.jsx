import ServiceComponent from './Service-Component/Service-Component'

function App() {
  return (
    <>
      <ServiceComponent
        name="my-node-service"
        functions={["/", "/service-js"]}
      />
      <ServiceComponent
        name="matrix-mult-service"
        functions={["/", "/hello", "/multiply"]}
      />
    </>
  )
}

export default App
