discard """
  action: "reject"
  line: 29
  errormsg: "\'vectFunc\' doesn't have a concrete type, due to unspecified generic parameters."
"""

type
  # simple vector of declared fixed length
  vector[N : static[int]] = array[0..N-1, float]

proc `*`[T](x: float, a: vector[T]): vector[T] =
  # multiplication by scalar
  for ii in 0..high(a):
    result[ii] = a[ii]*x

let
  # define a vector of length 3
  x: vector[3] = [1.0, 3.0, 5.0]

proc vectFunc[T](x: vector[T]): vector[T] {.procvar.} =
  # Define a vector function
  result = 2.0*x

proc passVectFunction[T](g: proc(x: vector[T]): vector[T], x: vector[T]): vector[T] =
  # pass a vector function as input in another procedure
  result = g(x)

let
  xNew = passVectFunction(vectFunc,x)
