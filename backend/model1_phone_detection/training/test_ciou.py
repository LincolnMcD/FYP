"""Check batched CIoU values and gradients against the original scalar loss."""

import unittest

import torch

from training.loss import _ciou_xywh, _assigned_box_loss


def scalar_ciou(a, b):
    eps = 1e-7
    amin, amax = a[:2]-a[2:]/2, a[:2]+a[2:]/2
    bmin, bmax = b[:2]-b[2:]/2, b[:2]+b[2:]/2
    intersection = (torch.minimum(amax,bmax)-torch.maximum(amin,bmin)).clamp(min=0).prod()
    iou = intersection / ((amax-amin).clamp(min=0).prod()+(bmax-bmin).clamp(min=0).prod()-intersection+eps)
    distance = ((a[:2]-b[:2])**2).sum()
    diagonal = ((torch.maximum(amax,bmax)-torch.minimum(amin,bmin))**2).sum()+eps
    aspect = 4/torch.pi**2*(torch.atan(b[2]/(b[3]+eps))-torch.atan(a[2]/(a[3]+eps)))**2
    alpha = aspect/(1-iou+aspect+eps)
    return iou-distance/diagonal-alpha*aspect


class CiouTests(unittest.TestCase):
    def test_values_and_gradients(self):
        for dtype in (torch.float32, torch.float64):
            generator = torch.Generator().manual_seed(12)
            a = torch.rand(40, 4, generator=generator, dtype=dtype).requires_grad_()
            b = torch.rand(40, 4, generator=generator, dtype=dtype).requires_grad_()
            actual = _ciou_xywh(a, b)
            expected = torch.stack([scalar_ciou(x, y) for x,y in zip(a,b)])
            torch.testing.assert_close(actual, expected)
            actual_grads = torch.autograd.grad(actual.mean(), (a,b), retain_graph=True)
            expected_grads = torch.autograd.grad(expected.mean(), (a,b))
            for x,y in zip(actual_grads,expected_grads):
                torch.testing.assert_close(x,y)

    def test_gathered_regression_and_gradients(self):
        torch.manual_seed(12)
        logits = torch.randn(2,4,8,6, dtype=torch.float64, requires_grad=True)
        assignments = [(0,1,2,torch.tensor([.2,.3,.1,.2],dtype=torch.float64)),
                       (1,4,3,torch.tensor([.6,.5,.3,.2],dtype=torch.float64)),
                       (0,5,1,torch.tensor([.3,.7,.1,.1],dtype=torch.float64))]
        actual = _assigned_box_loss(logits,assignments)
        losses = []
        for batch,gy,gx,target in assignments:
            raw = logits[batch,:,gy,gx]
            offset = .5+1.5*raw[:2].tanh()
            size = raw[2:].sigmoid()
            box = torch.stack(((gx+offset[0])/6,(gy+offset[1])/8,size[0],size[1]))
            losses.append(1-scalar_ciou(box,target))
        expected = torch.stack(losses).mean()
        torch.testing.assert_close(actual,expected)
        torch.testing.assert_close(torch.autograd.grad(actual,logits,retain_graph=True)[0],
                                   torch.autograd.grad(expected,logits)[0])

    def test_empty_and_degenerate_boxes(self):
        logits = torch.randn(2,4,8,8,requires_grad=True)
        zero = _assigned_box_loss(logits,[])
        zero.backward()
        self.assertEqual(float(zero.detach()),0.)
        self.assertTrue((logits.grad==0).all())
        boxes = torch.tensor([[.5,.5,.2,.2],[0.,0.,1e-9,1e-9],[.1,.1,.1,.1]],requires_grad=True)
        targets = torch.tensor([[.5,.5,.2,.2],[1.,1.,1e-9,1e-9],[.9,.9,.1,.1]])
        result = _ciou_xywh(boxes,targets)
        torch.testing.assert_close(result,torch.stack([scalar_ciou(a,b) for a,b in zip(boxes,targets)]))
        result.sum().backward()
        self.assertTrue(torch.isfinite(boxes.grad).all())


if __name__ == "__main__":
    unittest.main()
